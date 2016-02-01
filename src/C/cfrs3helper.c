/*
 * Adapted from aws4c.c
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <curl/curl.h>
#include <openssl/hmac.h>
#include <openssl/evp.h>
#include <openssl/bio.h>
#include <openssl/buffer.h>
#include "shared.h"

static char *S3Host     = "s3.amazonaws.com";     /// <AWS S3 host
static char *awsKeyID = NULL;
static char *awsKey = NULL;
static char *awsAccessControl = NULL;
static char * awsMimeType = NULL;
static int useRrs = 0;  /// <Use reduced redundancy storage

/// Set AWS account access key
/// \param key new AWS authentication key
void aws_set_key ( char * const key )
{ awsKey = key == NULL ? NULL : strdup(key);}

/// Set AWS account access key ID
/// \param keyid new AWS key ID
void aws_set_keyid ( char * const keyid )
{ awsKeyID = keyid == NULL ? NULL :  strdup(keyid);}

void aws_set_accesscontrol( char * const accesscontrol )
{ awsAccessControl = accesscontrol == NULL ? NULL : strdup(accesscontrol); }

void aws_set_mimetype( char * const mimetype )
{ awsMimeType = mimetype == NULL ? NULL : strdup(mimetype); }

IOStreamDescriptor * aws_iobuf_new () {
  IOStreamDescriptor * bf = malloc(sizeof(IOStreamDescriptor));
  memset(bf, 0, sizeof(IOStreamDescriptor));
  return bf;
}

 /// Encode a binary into base64 buffer
 /// \param input binary data  text
 /// \param length length of the input text
 /// \internal
 /// \return a newly allocated buffer with base64 encoded data.
 static char *__b64_encode(const unsigned char *input, int length)
 {
   BIO *bmem, *b64;
   BUF_MEM *bptr;

   b64 = BIO_new(BIO_f_base64());
   bmem = BIO_new(BIO_s_mem());
   b64 = BIO_push(b64, bmem);
   BIO_write(b64, input, length);
   if(BIO_flush(b64))
    ; /* make gcc 4.1.2 happy */
   BIO_get_mem_ptr(b64, &bptr);

   char *buff = (char *)malloc(bptr->length);
   memcpy(buff, bptr->data, bptr->length-1);
   buff[bptr->length-1] = 0;

   BIO_free_all(b64);

   return buff;
 }

 /// Get Request Date
 /// \internal
 /// \return date in HTTP format
 static char * __aws_get_httpdate ()
 {
   static char dTa[256];
   time_t t = time(NULL);
   struct tm * gTime = gmtime ( & t );
   memset ( dTa, 0 , sizeof(dTa));
   strftime ( dTa, sizeof(dTa), "%a, %d %b %Y %H:%M:%S +0000", gTime );
   return dTa;
 }

 static char* __aws_sign ( char * const str )
 {
   HMAC_CTX ctx;
   unsigned char MD[256];
   unsigned len;

   HMAC(EVP_sha1(), awsKey, strlen(awsKey), (unsigned char*) str, strlen(str),
             (unsigned char*)&MD, &len);

   char * b64 = __b64_encode (MD,len);

   return b64;
 }

/// Get S3 Request signature
/// \internal
/// \param resource -- URI of the object
/// \param resSize --  size of the resoruce buffer
/// \param date -- HTTP date
/// \param method -- HTTP method
/// \param bucket -- bucket.
/// \param file --  file
/// \return fills up resource and date parameters, also.
///         returns request signature to be used with Authorization header
char * getStringToSign (
     char ** date,
     char * const method,
     char * const bucket,
     char * const file )
{
  char  reqToSign[2048];
  char  acl[32];
  char  rrs[64];
  char resource[1024];
  int resSize = sizeof(resource);

  /// \todo Change the way RRS is handled.  Need to pass it in

  * date = __aws_get_httpdate();

  memset ( resource,0,resSize);
  if ( bucket != NULL )
    snprintf ( resource, resSize,"%s/%s", bucket, file );
  else
    snprintf ( resource, resSize,"%s", file );

  if (awsAccessControl)
    snprintf( acl, sizeof(acl), "x-amz-acl:%s\n", awsAccessControl);
  else
    acl[0] = 0;

  if (useRrs)
    strncpy( rrs, "x-amz-storage-class:REDUCED_REDUNDANCY\n", sizeof(rrs));
  else
    rrs[0] = 0;


  snprintf ( reqToSign, sizeof(reqToSign),"%s\n\n%s\n%s\n%s%s/%s",
     method,
     awsMimeType ? awsMimeType : "",
     *date,
     acl,
     rrs,
     resource );

  // EU: If bucket is in virtual host name, remove bucket from path
  if (bucket && strncmp(S3Host, bucket, strlen(bucket)) == 0)
    snprintf ( resource, resSize,"%s", file );

  return __aws_sign(reqToSign);
}

/// Chomp (remove the trailing '\n' from the string
/// \param str string
static void __chomp ( char  * str ) {
  if ( str[0] == 0 ) return;
  int ln = strlen(str);
  ln--;
  if ( str[ln] == '\n' ) str[ln] = 0;
  if ( ln == 0 ) return ;
  ln--;
  if ( str[ln] == '\r' ) str[ln] = 0;
}

/// Suppress outputs to stdout
static size_t writedummyfunc ( void * ptr, size_t size, size_t nmemb, void * stream ) {
  // Debug: printf("READ: %s\n", (char*)ptr);
  return nmemb * size;
}

/// Handles sending of the data
/// \param ptr pointer to the incoming data
/// \param size size of the data member
/// \param nmemb number of data memebers
/// \param stream pointer to I/O buffer
/// \return number of bytes written
static size_t readfunc ( void * ptr, size_t size, size_t nmemb, void * stream ) {
  return fread(ptr, size, nmemb, ((IOStreamDescriptor *)stream)->fd);
}

/// Process incming header
/// \param ptr pointer to the incoming data
/// \param size size of the data member
/// \param nmemb number of data memebers
/// \param stream pointer to I/O buffer
/// \return number of bytes processed
static size_t header ( void * ptr, size_t size, size_t nmemb, void * stream )
{
  IOStreamDescriptor * b = stream;

  if (!strncmp ( ptr, "HTTP/1.1", 8 ))
    {
      b->result = strdup ( ptr + 9 );
      __chomp(b->result);
      b->code   = atoi ( ptr + 9 );
    }
  else if ( !strncmp ( ptr, "ETag: ", 6 ))
    {
      b->eTag = strdup ( ptr + 6 );
      __chomp(b->eTag);
    }
  else if ( !strncmp ( ptr, "Last-Modified: ", 14 ))
    {
      b->lastMod = strdup ( ptr + 15 );
      __chomp(b->lastMod);
    }
  else if ( !strncmp ( ptr, "Content-Length: ", 15 ))
    {
      b->contentLen = atoi ( ptr + 16 );
    }

  return nmemb * size;
}

void cr_aws_put_run(IOParameters params) {

  curl_global_init (CURL_GLOBAL_ALL);
  char work_buf[1024];

  CURL* ch =  curl_easy_init( );
  struct curl_slist *slist=NULL;

  if (awsMimeType) {
    snprintf (work_buf, sizeof(work_buf), "Content-Type: %s", awsMimeType);
    slist = curl_slist_append(slist, work_buf);
  }

  if (awsAccessControl) {
    snprintf (work_buf, sizeof(work_buf), "x-amz-acl: %s", awsAccessControl);
    slist = curl_slist_append(slist, work_buf);
  }

  if (useRrs) {
    strncpy (work_buf, "x-amz-storage-class: REDUCED_REDUNDANCY", sizeof(work_buf));
    slist = curl_slist_append(slist, work_buf); }

  snprintf (work_buf, sizeof(work_buf), "Date: %s", params.date_str);
  slist = curl_slist_append(slist, work_buf);
  snprintf (work_buf, sizeof(work_buf), "Authorization: AWS %s:%s", awsKeyID, params.signature);
  slist = curl_slist_append(slist, work_buf);

  snprintf (work_buf, sizeof(work_buf), "http://%s.%s/%s", params.bucket, S3Host , params.resource_name);

  curl_easy_setopt ( ch, CURLOPT_READDATA, params.bf );
  curl_easy_setopt ( ch, CURLOPT_READFUNCTION, params.callback );

  curl_easy_setopt ( ch, CURLOPT_HTTPHEADER, slist);
  curl_easy_setopt ( ch, CURLOPT_URL, work_buf );
  //curl_easy_setopt ( ch, CURLOPT_READDATA, params.bf );
  curl_easy_setopt ( ch, CURLOPT_WRITEFUNCTION, writedummyfunc );
  curl_easy_setopt ( ch, CURLOPT_HEADERFUNCTION, header );
  curl_easy_setopt ( ch, CURLOPT_HEADERDATA, params.bf );
  curl_easy_setopt ( ch, CURLOPT_VERBOSE, 0 );
  curl_easy_setopt ( ch, CURLOPT_UPLOAD, 1 );
  curl_easy_setopt ( ch, CURLOPT_INFILESIZE, params.bf->len );
  curl_easy_setopt ( ch, CURLOPT_FOLLOWLOCATION, 1 );

  int  sc  = curl_easy_perform(ch);
  curl_slist_free_all(slist);
  curl_easy_cleanup(ch);
}

void cr_aws_put(
  const char *date_str,
  const char *signature,
  const char *resource_name,
  const char *resource_path,
  const char *bucket) {
    // TODO Free bf after work OR better: zero out and re use it!
    // Right now this is a huge memory leak...
    IOStreamDescriptor *bf = aws_iobuf_new();
    bf->fd = fopen(resource_path, "rb");
    fseek(bf->fd, 0L, SEEK_END);
    bf->len = ftell(bf->fd);
    fseek(bf->fd, 0L, SEEK_SET);

    IOParameters params;
    params.date_str = date_str;
    params.signature = signature;
    params.resource_name = resource_name;
    params.resource_path = resource_path;
    params.bucket = bucket;
    params.bf = bf;
    params.callback = readfunc;
    cr_aws_put_run(params);

    fclose(bf->fd);
}

/*
 * Do not use! If we use CURL directly and compress our file on the fly,
 * then we will hang forever due to the promised file size being off.
 */
void cr_aws_put_compress(
  const char *date_str,
  const char *signature,
  const char *resource_name,
  const char *resource_path,
  const char *bucket) {

    IOStreamDescriptor *bf = aws_iobuf_new();
    bf->fd = fopen(resource_path, "rb");
    fseek(bf->fd, 0L, SEEK_END);
    bf->len = ftell(bf->fd);
    fseek(bf->fd, 0L, SEEK_SET);

    IOParameters params;
    params.date_str = date_str;
    params.signature = signature;
    params.resource_name = resource_name;
    params.resource_path = resource_path;
    params.bucket = bucket;
    params.bf = bf;
    params.level = 9;
    params.remote = cr_aws_put_run;
    mzx_copy_deflate_remote(params);

    fclose(bf->fd);
}
