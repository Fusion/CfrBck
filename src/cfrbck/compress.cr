@[Link("miniz")]
lib LibMini
  fun mz_compress(pDest: UInt8*, pDest_len: UInt32*, pSource: UInt8*, source_len: Int32): Int8
  fun mz_uncompress(pDest: UInt8*, pDest_len: UInt32*, pSource: UInt8*, source_len: Int32): Int8

  type Mz_uint = UInt16
  type Mz_uint8 = UInt8
  type Mz_uint16 = UInt16
  type Mz_uint32 = UInt32

  enum Tdefl_status
    TDEFL_STATUS_BAD_PARAM = -2,
    TDEFL_STATUS_PUT_BUF_FAILED = -1,
    TDEFL_STATUS_OKAY = 0,
    TDEFL_STATUS_DONE = 1,
  end

  enum Tdefl_flags
    TDEFL_WRITE_ZLIB_HEADER             = 0x01000,
    TDEFL_COMPUTE_ADLER32               = 0x02000,
    TDEFL_GREEDY_PARSING_FLAG           = 0x04000,
    TDEFL_NONDETERMINISTIC_PARSING_FLAG = 0x08000,
    TDEFL_RLE_MATCHES                   = 0x10000,
    TDEFL_FILTER_MATCHES                = 0x20000,
    TDEFL_FORCE_ALL_STATIC_BLOCKS       = 0x40000,
    TDEFL_FORCE_ALL_RAW_BLOCKS          = 0x80000
  end

  struct Tdefl_compressor
    tdefl_put_buf_func_ptr m_pPut_buf_func;
    void *m_pPut_buf_user;
    mz_uint m_flags, m_max_probes[2];
    int m_greedy_parsing;
    mz_uint m_adler32, m_lookahead_pos, m_lookahead_size, m_dict_size;
    mz_uint8 *m_pLZ_code_buf, *m_pLZ_flags, *m_pOutput_buf, *m_pOutput_buf_end;
    mz_uint m_num_flags_left, m_total_lz_bytes, m_lz_code_buf_dict_pos, m_bits_in, m_bit_buffer;
    mz_uint m_saved_match_dist, m_saved_match_len, m_saved_lit, m_output_flush_ofs, m_output_flush_remaining, m_finished, m_block_index, m_wants_to_finish;
    tdefl_status m_prev_return_status;
    const void *m_pIn_buf;
    void *m_pOut_buf;
    size_t *m_pIn_buf_size, *m_pOut_buf_size;
    tdefl_flush m_flush;
    const mz_uint8 *m_pSrc;
    size_t m_src_buf_left, m_out_buf_ofs;
    mz_uint8 m_dict[TDEFL_LZ_DICT_SIZE + TDEFL_MAX_MATCH_LEN - 1];
    mz_uint16 m_huff_count[TDEFL_MAX_HUFF_TABLES][TDEFL_MAX_HUFF_SYMBOLS];
    mz_uint16 m_huff_codes[TDEFL_MAX_HUFF_TABLES][TDEFL_MAX_HUFF_SYMBOLS];
    mz_uint8 m_huff_code_sizes[TDEFL_MAX_HUFF_TABLES][TDEFL_MAX_HUFF_SYMBOLS];
    mz_uint8 m_lz_code_buf[TDEFL_LZ_CODE_BUF_SIZE];
    mz_uint16 m_next[TDEFL_LZ_DICT_SIZE];
    mz_uint16 m_hash[TDEFL_LZ_HASH_SIZE];
    mz_uint8 m_output_buf[TDEFL_OUT_BUF_SIZE];
  end

#  fun tdefl_init(tdefl_compressor *d, tdefl_put_buf_func_ptr pPut_buf_func, void *pPut_buf_user, int flags): Tdefl_status
end

module Compress extend self
  def compress
    target_path_ptr = Pointer(UInt8).malloc(32768)
    size_ptr = Pointer(UInt32).malloc(1)
    size_ptr.value = 32767_u32
    compressme = Slice(UInt8).new(16384)
#    File.open("README.md", "r")  do |file_in|
#      count = file_in.read(compressme)
#      partial_buffer = Slice(UInt8).new(count) { |i| compressme[i] }
#      res = LibMini.mz_compress(target_path_ptr, size_ptr, partial_buffer, count)
#      new_target_path_ptr = Pointer(UInt8).malloc(32768)
#      new_size_ptr = Pointer(UInt32).malloc(1)
#      new_size_ptr.value = 32767_u32
#      res = LibMini.mz_uncompress(new_target_path_ptr, new_size_ptr, target_path_ptr, size_ptr.value)
#      dest_slice = Slice(UInt8).new(new_target_path_ptr, new_size_ptr.value)
#      File.open("bogus.test", "w") do |file_out|
#        file_out.write(dest_slice)
#      end
#    end
    infile_size = File.size("README.md")
    File.open("README.md", "r")  do |file_in|
      infile_remaining = infile_size
      num_probes = 768
      comp_flags = LibMini::Tdefl_flags::TDEFL_WRITE_ZLIB_HEADER.to_i | 768
      #       status = tdefl_init(&g_deflator, NULL, NULL, comp_flags);
      status = 1
    end
  end
end
