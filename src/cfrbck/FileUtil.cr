lib LibC
	fun readlink(filename: Char*, buffer: Char*, size: Int): Int
end

require "file"

module FileUtil extend self
  def copy(source_path, dest_path)
		File.open(source_path, "r")  do |file_in|
			File.open(dest_path, "w") do |file_out|
				bufsize = 4096
				buffer = Slice(UInt8).new(bufsize)
				complete = false
				until complete
					count = file_in.read(buffer)
					if count == bufsize
						file_out.write(buffer)
					else
						partial_buffer = Slice(UInt8).new(count) { |i| buffer[i] }
						file_out.write(partial_buffer)
						complete = true
					end
				end
			end
		end
  end

  def readlink(link_path)
    target_path_ptr = Pointer(UInt8).malloc(1025)
    read_count = LibC.readlink(link_path, target_path_ptr, 1024)
    String.new(target_path_ptr, read_count)
  end
end
