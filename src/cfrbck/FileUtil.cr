lib LibC
	fun readlink(filename: Char*, buffer: Char*, size: Int): Int
end

require "file"
require "proc"

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

	class Math
		def initialize
			# init for md4
			@mask = (1 << 32) - 1

		  @f = long_proc_three {|x, y, z| x & y | x.^(@mask) & z}
		  @g = long_proc_three {|x, y, z| x & y | x & z | y & z}
		  @h = long_proc_three {|x, y, z| x ^ y ^ z}
		  @r = long_proc_two {|v, s| (v << s).&(@mask) | (v.&(@mask) >> (32 - s))}

			@a, @b, @c, @d = 1732584193_u32, 4023233417_u32, 2562383102_u32, 271733878_u32
			#
		end

		def long_proc_two(&block: UInt32, UInt32 -> UInt32)
			block
		end

		def long_proc_three(&block: UInt32, UInt32, UInt32 -> UInt32)
			block
		end

		def checksum(path)
			if true
				digest = LocalCrypto::MD5Delegate.new
				File.open(path, "r")  do |file_in|
					bufsize = 4096
					buffer = Slice(UInt8).new bufsize
					complete = false
					until complete
						count = file_in.read buffer
						if count == bufsize
							digest.update buffer
						else
							partial_buffer = Slice(UInt8).new(count) { |i| buffer[i] }
							padded_buffer = padded(partial_buffer)
							digest.update padded_buffer
							complete = true
						end
					end
				end
				digest.finish
				cs = digest.to_s
			else
				File.open(path, "r")  do |file_in|
					bufsize = 4096
					buffer = Slice(UInt8).new bufsize
					complete = false
					until complete
						count = file_in.read buffer
						if count == bufsize
							md4 buffer
						else
							partial_buffer = Slice(UInt8).new(count) { |i| buffer[i] }
							padded_buffer = padded(partial_buffer)
							md4 padded_buffer
							complete = true
						end
					end
				end
				cs = @a.to_s(16) + ":" + @b.to_s(16) + ":" + @c.to_s(16) + ":" + @d.to_s(16)
			end
			cs
		end

		private def padded(raw_buffer)
			count = raw_buffer.size
			bit_len = count << 3 # to bits
			padded_count = count + 1 # for \x80
			while (padded_count % 64) != 56
				padded_count += 1
			end
			buffer = Slice(UInt8).new(padded_count) { |i|
				case i
				when .< count
					raw_buffer[i]
				when count
					128_u8
				else
					0_u8
				end
			}
			buffer
		end

		private def md4(x)
			aa, bb, cc, dd = @a, @b, @c, @d

			[0, 4, 8, 12].each {|i|
	      @a = @r.call(@a + @f.call(@b, @c, @d) + x[i],  3_u32); i += 1
	      @d = @r.call(@d + @f.call(@a, @b, @c) + x[i],  7_u32); i += 1
	      @c = @r.call(@c + @f.call(@d, @a, @b) + x[i], 11_u32); i += 1
	      @b = @r.call(@b + @f.call(@c, @d, @a) + x[i], 19_u32)
	    }

			[0, 1, 2, 3].each {|i|
				@a = @r.call(@a + @g.call(@b, @c, @d) + x[i] + 0x5a827999,  3_u32); i += 4
				@d = @r.call(@d + @g.call(@a, @b, @c) + x[i] + 0x5a827999,  5_u32); i += 4
				@c = @r.call(@c + @g.call(@d, @a, @b) + x[i] + 0x5a827999,  9_u32); i += 4
				@b = @r.call(@b + @g.call(@c, @d, @a) + x[i] + 0x5a827999, 13_u32)
			}

			[0, 2, 1, 3].each {|i|
	      @a = @r.call(@a + @h.call(@b, @c, @d) + x[i] + 0x6ed9eba1,  3_u32); i += 8
	      @d = @r.call(@d + @h.call(@a, @b, @c) + x[i] + 0x6ed9eba1,  9_u32); i -= 4
	      @c = @r.call(@c + @h.call(@d, @a, @b) + x[i] + 0x6ed9eba1, 11_u32); i += 8
	      @b = @r.call(@b + @h.call(@c, @d, @a) + x[i] + 0x6ed9eba1, 15_u32)
	    }

			@a = (@a + aa) & @mask
	    @b = (@b + bb) & @mask
	    @c = (@c + cc) & @mask
	    @d = (@d + dd) & @mask
		end
	end
end
