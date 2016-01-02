require "openssl"

module LocalCrypto
  enum Algorithm
    MD4
    MD5
  end

  class MD5Delegate
    include OpenSSL

    def initialize(@ideal_size = 4096)
      @digest = Digest.new "md5"
    end

    def update(data : String | Slice)
      @digest.update data
    end

    def finish
      # noop!
    end

    def to_s
      @digest.to_s
    end
  end

  class MD4Impl
    def initialize(@ideal_size = 4096)
			@mask = (1 << 32) - 1

		  @f = long_proc_three {|x, y, z| x & y | x.^(@mask) & z}
		  @g = long_proc_three {|x, y, z| x & y | x & z | y & z}
		  @h = long_proc_three {|x, y, z| x ^ y ^ z}
		  @r = long_proc_two {|v, s| (v << s).&(@mask) | (v.&(@mask) >> (32 - s))}

			@a, @b, @c, @d = 1732584193_u32, 4023233417_u32, 2562383102_u32, 271733878_u32
    end

		def long_proc_two(&block: UInt32, UInt32 -> UInt32)
			block
		end

		def long_proc_three(&block: UInt32, UInt32, UInt32 -> UInt32)
			block
		end

		private def padded(raw_data)
			count = raw_data.size
			bit_len = count << 3 # to bits
			padded_count = count + 1 # for \x80
			while (padded_count % 64) != 56
				padded_count += 1
			end
			data = Slice(UInt8).new(padded_count) { |i|
				case i
				when .< count
					raw_data[i]
				when count
					128_u8
				else
					0_u8
				end
			}
			data
		end

    def update(data : String | Slice)
      if data.size < @ideal_size
        data = padded data
      end

			aa, bb, cc, dd = @a, @b, @c, @d

			[0, 4, 8, 12].each {|i|
	      @a = @r.call(@a + @f.call(@b, @c, @d) + data[i],  3_u32); i += 1
	      @d = @r.call(@d + @f.call(@a, @b, @c) + data[i],  7_u32); i += 1
	      @c = @r.call(@c + @f.call(@d, @a, @b) + data[i], 11_u32); i += 1
	      @b = @r.call(@b + @f.call(@c, @d, @a) + data[i], 19_u32)
	    }

			[0, 1, 2, 3].each {|i|
				@a = @r.call(@a + @g.call(@b, @c, @d) + data[i] + 0x5a827999,  3_u32); i += 4
				@d = @r.call(@d + @g.call(@a, @b, @c) + data[i] + 0x5a827999,  5_u32); i += 4
				@c = @r.call(@c + @g.call(@d, @a, @b) + data[i] + 0x5a827999,  9_u32); i += 4
				@b = @r.call(@b + @g.call(@c, @d, @a) + data[i] + 0x5a827999, 13_u32)
			}

			[0, 2, 1, 3].each {|i|
	      @a = @r.call(@a + @h.call(@b, @c, @d) + data[i] + 0x6ed9eba1,  3_u32); i += 8
	      @d = @r.call(@d + @h.call(@a, @b, @c) + data[i] + 0x6ed9eba1,  9_u32); i -= 4
	      @c = @r.call(@c + @h.call(@d, @a, @b) + data[i] + 0x6ed9eba1, 11_u32); i += 8
	      @b = @r.call(@b + @h.call(@c, @d, @a) + data[i] + 0x6ed9eba1, 15_u32)
	    }

			@a = (@a + aa) & @mask
	    @b = (@b + bb) & @mask
	    @c = (@c + cc) & @mask
	    @d = (@d + dd) & @mask
    end

    def finish
      # noop!
    end

    def to_s
			cs = @a.to_s(16) + ":" + @b.to_s(16) + ":" + @c.to_s(16) + ":" + @d.to_s(16)
    end
  end
end
