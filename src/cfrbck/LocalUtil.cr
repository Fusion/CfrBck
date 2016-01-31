module LocalUtil extend self

  class Actor
    def copy(source_path, dest_path, compress?)
      case compress?
      when FileUtil::Action::COMPRESS
        compress_copy(source_path, dest_path)
      when FileUtil::Action::EXPAND
        expand_copy(source_path, dest_path)
      else
        preserve_copy(source_path, dest_path)
      end
    end

    private def compress_copy(source_path, dest_path)
      if 0 != Compress.compress(source_path, dest_path)
        raise FileUtil::FileCompressionException.new "Error compressing #{source_path}"
      end
    end

    private def expand_copy(source_path, dest_path)
      if 0 != Compress.expand(source_path, dest_path)
        raise FileUtil::FileCompressionException.new "Error expanding #{source_path}"
      end
    end

    def preserve_copy(source_path, dest_path)
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
  end
end
