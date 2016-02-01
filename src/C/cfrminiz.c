#define MINIZ_NO_STDIO
#define MINIZ_NO_ARCHIVE_APIS
#define MINIZ_NO_TIME
#define MINIZ_NO_ZLIB_APIS
#define MINIZ_NO_MALLOC
#include "miniz.c"
#include "shared.h"

#include <stdio.h>
#include <curl/curl.h>

#define COMP_OUT_BUF_SIZE (1024*512)
#define my_max(a,b) (((a) > (b)) ? (a) : (b))
#define my_min(a,b) (((a) < (b)) ? (a) : (b))
#define IN_BUF_SIZE (1024*512)
#define OUT_BUF_SIZE (1024*512)
typedef unsigned char uint8;
// Once allocated, we will re use this guy time and again
// and never free it
static tdefl_compressor *g_deflator = 0;
// Same here
static tinfl_decompressor *inflator = 0;
// Impacts compression level
static const mz_uint s_tdefl_num_probes[11] = { 0, 1, 6, 32,  16, 32, 128, 256,  512, 768, 1500 };

// Scope limited to this file
static size_t avail_out;
static size_t avail_in;
static uint8 s_inbuf[IN_BUF_SIZE];
static const void *next_in;
static uint8 s_outbuf[OUT_BUF_SIZE];
static void *next_out;
static size_t total_in;
static size_t total_out;
static unsigned int infile_remaining;

void __init_globals() {
  avail_out = COMP_OUT_BUF_SIZE;
  avail_in  = 0;
  next_in = s_inbuf;
  next_out = s_outbuf;
  total_in = 0;
  total_out = 0;
}

// Callback invoked by CURL/friends to read data to push to remote destination
size_t mzx_copy_deflate_remote_stepper(void * ptr, size_t size, size_t nmemb, void * stream) {
  tdefl_status status;
  size_t in_bytes, out_bytes;
  unsigned int n = nmemb * size;
  unsigned int actual_read_count;
  if(infile_remaining == 0) {
    printf("0:DONE\n");
    return CURL_READFUNC_ABORT;
  }
  if ((actual_read_count = fread(ptr, 1, n, ((IOStreamDescriptor *)stream)->fd)) == 0) {
    printf("READ 0\n");
    return 0;
  }
  printf("READ %u out of %u\n", actual_read_count, n);
  in_bytes = n;
  out_bytes = n;
  status = tdefl_compress(g_deflator, ptr, &in_bytes, next_out, &out_bytes, TDEFL_FINISH);
  if(status == TDEFL_STATUS_DONE) {
    infile_remaining = 0;
  }
  printf("STATUS = %d\n", status);

  return out_bytes;
}

/*
 * Experimental: do not use as I have yet to figure out whether there is a way
 * to convince our client (in my case CURL) to accept an early termination
 * that will not fulfill the promise of sending as many bites as
 * originally counted.
 */
int mzx_copy_deflate_remote(IOParameters params) {
  FILE *pInfile = fopen(params.resource_path, "rb");
  if (!pInfile) {
    return EXIT_FAILURE;
  }
  fseek(pInfile, 0, SEEK_END);
  long file_loc = ftell(pInfile);
  fseek(pInfile, 0, SEEK_SET);
  unsigned int infile_size = (unsigned int)file_loc;

  tdefl_status status;
  infile_remaining = infile_size;
  mz_uint comp_flags = TDEFL_WRITE_ZLIB_HEADER | s_tdefl_num_probes[MZ_MIN(10, params.level)] | ((params.level <= 3) ? TDEFL_GREEDY_PARSING_FLAG : 0);
  if (!params.level)
    comp_flags |= TDEFL_FORCE_ALL_RAW_BLOCKS;
  // Initialize the low-level compressor.
  if(!g_deflator)
    g_deflator = malloc(sizeof(tdefl_compressor));
  status = tdefl_init(g_deflator, NULL, NULL, comp_flags);
  if (status != TDEFL_STATUS_OKAY) {
     fclose(pInfile);
     return EXIT_FAILURE;
  }

  __init_globals();
  params.callback = mzx_copy_deflate_remote_stepper;
  params.remote(params);

  fclose(pInfile);
  return EXIT_SUCCESS;
}

int mzx_copy_deflate(const char *pDst_filename, const char *pSrc_filename, int level) {
  FILE *pInfile = fopen(pSrc_filename, "rb");
  if (!pInfile) {
    return EXIT_FAILURE;
  }
  fseek(pInfile, 0, SEEK_END);
  long file_loc = ftell(pInfile);
  fseek(pInfile, 0, SEEK_SET);
  unsigned int infile_size = (unsigned int)file_loc;
  FILE *pOutfile = fopen(pDst_filename, "wb");
  if (!pOutfile) {
    fclose(pInfile);
    return EXIT_FAILURE;
  }

  tdefl_status status;
  infile_remaining = infile_size;
  mz_uint comp_flags = TDEFL_WRITE_ZLIB_HEADER | s_tdefl_num_probes[MZ_MIN(10, level)] | ((level <= 3) ? TDEFL_GREEDY_PARSING_FLAG : 0);
  if (!level)
    comp_flags |= TDEFL_FORCE_ALL_RAW_BLOCKS;
  // Initialize the low-level compressor.
  if(!g_deflator)
    g_deflator = malloc(sizeof(tdefl_compressor));
  status = tdefl_init(g_deflator, NULL, NULL, comp_flags);
  if (status != TDEFL_STATUS_OKAY) {
     fclose(pOutfile); fclose(pInfile);
     return EXIT_FAILURE;
  }

  __init_globals();

  for(;;) {
    size_t in_bytes, out_bytes;
    if (!avail_in) {
      unsigned int n = my_min(IN_BUF_SIZE, infile_remaining);
      if (fread(s_inbuf, 1, n, pInfile) != n) {
        fclose(pOutfile); fclose(pInfile);
        return EXIT_FAILURE;
      }
      next_in = s_inbuf;
      avail_in = n;
      infile_remaining -= n;
    }

    in_bytes = avail_in;
    out_bytes = avail_out;
    // Compress as much of the input as possible (or all of it) to the output buffer.
    status = tdefl_compress(g_deflator, next_in, &in_bytes, next_out, &out_bytes, infile_remaining ? TDEFL_NO_FLUSH : TDEFL_FINISH);

    next_in = (const char *)next_in + in_bytes;
    avail_in -= in_bytes;
    total_in += in_bytes;

    next_out = (char *)next_out + out_bytes;
    avail_out -= out_bytes;
    total_out += out_bytes;

    if ((status != TDEFL_STATUS_OKAY) || (!avail_out)) {
      // Output buffer is full, or compression is done or failed, so write buffer to output file.
      unsigned int n = COMP_OUT_BUF_SIZE - (unsigned int)avail_out;
      if (fwrite(s_outbuf, 1, n, pOutfile) != n) {
       fclose(pOutfile); fclose(pInfile);
       return EXIT_FAILURE;
      }
      next_out = s_outbuf;
      avail_out = COMP_OUT_BUF_SIZE;
    }

    if (status == TDEFL_STATUS_DONE) {
      break;
    }
    else if (status != TDEFL_STATUS_OKAY) {
      fclose(pOutfile); fclose(pInfile);
      return EXIT_FAILURE;
    }
  }

  fclose(pOutfile);
  fclose(pInfile);
  return EXIT_SUCCESS;
}

int mzx_copy_inflate(const char *pDst_filename, const char *pSrc_filename) {
  FILE *pInfile = fopen(pSrc_filename, "rb");
  if (!pInfile) {
    return EXIT_FAILURE;
  }
  fseek(pInfile, 0, SEEK_END);
  long file_loc = ftell(pInfile);
  fseek(pInfile, 0, SEEK_SET);
  unsigned int infile_size = (unsigned int)file_loc;
  infile_remaining = infile_size;
  FILE *pOutfile = fopen(pDst_filename, "wb");
  if (!pOutfile) {
    fclose(pInfile);
    return EXIT_FAILURE;
  }

  if(!inflator)
    inflator = malloc(sizeof(tinfl_decompressor));
  tinfl_init(inflator);

  __init_globals();

  for(;;) {
    size_t in_bytes, out_bytes;
    tinfl_status status;
    if (!avail_in) {
       // Input buffer is empty, so read more bytes from input file.
       unsigned int n = my_min(IN_BUF_SIZE, infile_remaining);

       if (fread(s_inbuf, 1, n, pInfile) != n) {
          fclose(pOutfile); fclose(pInfile);
          return EXIT_FAILURE;
       }

       next_in = s_inbuf;
       avail_in = n;

       infile_remaining -= n;
    }

    in_bytes = avail_in;
    out_bytes = avail_out;
    status = tinfl_decompress(inflator, (const mz_uint8 *)next_in, &in_bytes, s_outbuf, (mz_uint8 *)next_out, &out_bytes, (infile_remaining ? TINFL_FLAG_HAS_MORE_INPUT : 0) | TINFL_FLAG_PARSE_ZLIB_HEADER);

    avail_in -= in_bytes;
    next_in = (const mz_uint8 *)next_in + in_bytes;
    total_in += in_bytes;

    avail_out -= out_bytes;
    next_out = (mz_uint8 *)next_out + out_bytes;
    total_out += out_bytes;

    if ((status <= TINFL_STATUS_DONE) || (!avail_out)) {
       // Output buffer is full, or decompression is done, so write buffer to output file.
       unsigned int n = OUT_BUF_SIZE - (unsigned int)avail_out;
       if (fwrite(s_outbuf, 1, n, pOutfile) != n) {
          fclose(pOutfile); fclose(pInfile);
          return EXIT_FAILURE;
       }
       next_out = s_outbuf;
       avail_out = OUT_BUF_SIZE;
    }

    // If status is <= TINFL_STATUS_DONE then either decompression is done or something went wrong.
    if (status <= TINFL_STATUS_DONE) {
       if (status == TINFL_STATUS_DONE) {
          // Decompression completed successfully.
          break;
       }
       else { // Decompression failed.
          fclose(pOutfile); fclose(pInfile);
          return EXIT_FAILURE;
       }
    }
  }

  fclose(pOutfile);
  fclose(pInfile);
  return EXIT_SUCCESS;
}
