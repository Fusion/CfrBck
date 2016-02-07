module LocalUtil extend self

  class Actor
    def work_dir(s, d)
      d
    end

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
      if 0 != Compress.compress(source_path, dest_path.path)
        raise FileUtil::FileCompressionException.new "Error compressing #{source_path}"
      end
    end

    private def expand_copy(source_path, dest_path)
      if 0 != Compress.expand(source_path, dest_path.path)
        raise FileUtil::FileCompressionException.new "Error expanding #{source_path}"
      end
    end

    def preserve_copy(source_path, dest_path)
      File.open(source_path, "r")  do |file_in|
        File.open(dest_path.path, "w") do |file_out|
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

    def normalized_path(canon, path)
      FileUtil.normalized_path(canon, path)
    end

    def prepare(location_in, location_out)
      FileUtil.prepare(location_out)
    end

    def retrieve_catalog(location, new_catalog_id)
      FileUtil.retrieve_catalog(location, new_catalog_id)
    end

    def write_catalog(location, new_catalog_id, caller)
      FileUtil.write_catalog(location, new_catalog_id, caller)
    end

    def test
      # nil
    end
  end

end
