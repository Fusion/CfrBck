module PipeUtil extend self

  # We are going to use stderr as our out pipe while stdin will be out input
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
    end

    private def expand_copy(source_path, dest_path)
    end

    def preserve_copy(source_path, dest_path)
      puts "COPYING"
      File.open(source_path, "r")  do |file_in|
        bufsize = 4096
        buffer = Slice(UInt8).new(bufsize)
        complete = false
        until complete
          count = file_in.read(buffer)
          if count == bufsize
            STDERR.write(buffer)
          else
            partial_buffer = Slice(UInt8).new(count) { |i| buffer[i] }
            STDERR.write(partial_buffer)
            complete = true
          end
        end
      end
    end
  end
end
