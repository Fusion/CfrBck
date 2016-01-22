@[Link("miniz")]
lib LibMini
  fun mz_compress(pDest: UInt8*, pDest_len: UInt32*, pSource: UInt8*, source_len: Int32): Int8
  fun mz_uncompress(pDest: UInt8*, pDest_len: UInt32*, pSource: UInt8*, source_len: Int32): Int8

  fun mzx_copy_deflate(pDst_filename: UInt8*, pSrc_filename: UInt8*, level: Int32): Int8
  fun mzx_copy_inflate(pDst_filename: UInt8*, pSrc_filename: UInt8*): Int8

end

module Compress extend self
  def compress(source_path, dest_path)
    LibMini.mzx_copy_deflate(dest_path, source_path, 9)
  end

  def expand(source_path, dest_path)
    LibMini.mzx_copy_inflate(dest_path, source_path)
  end

  def test
    LibMini.mzx_copy_deflate("bogus.out", "README.md", 9)
    LibMini.mzx_copy_inflate("bogus.decrypted", "bogus.out")
    LibMini.mzx_copy_deflate("bogus2.out", "LICENSE", 9)
    LibMini.mzx_copy_inflate("bogus2.decrypted", "bogus2.out")
#    target_path_ptr = Pointer(UInt8).malloc(32768)
#    size_ptr = Pointer(UInt32).malloc(1)
#    size_ptr.value = 32767_u32
#    compressme = Slice(UInt8).new(16384)
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
  end
end
