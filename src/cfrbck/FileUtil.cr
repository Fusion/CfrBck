lib LibC
  fun readlink(filename: Char*, buffer: Char*, size: Int): Int
  fun symlink(target: Char*, link_path: Char*): Int
  fun chown(filename: Char*, owner: Int, group: Int): Int
  fun chmod(filename: Char*, mode: Int): Int
  #fun qsort(base : Void*, nel : Int32, width : Int32, cb : (Void*, Void*) -> Int32)
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

  def symlink(target, link_path, force = false)
    if 0 != LibC.symlink(target, link_path)
      raise "Unable to create symbolic link #{target} for #{link_path}" unless force
    end
  end

  def chown(file_path, owner, group, force = false)
    if 0 != LibC.chown(file_path, owner, group)
      raise "Unable to change ownerhsip to #{owner}:#{group} for file #{file_path}" unless force
    end
  end

  def chmod(file_path, mode, force = false)
    if 0 != LibC.chmod(file_path, mode)
      raise "Unable to change mode to #{mode} for file #{file_path}" unless force
    end
  end

  def canonical_path(path)
    File.expand_path(path)
  end

  def normalized_path(canon, path)
    canonp = File.join(canon, "")
    if !path.starts_with? canon
      raise "Attempt to normalize [#{path}] based on [#{canonp}] is not legal."
    end
    path.sub(canonp, "")
  end

  def sort_paths(paths : Array(String))
    sorted_paths = paths.clone
    #compar = ->(x : Void*, y : Void*) do (x as String*).value < (y as String*).value ? 1 : -1 end
    #LibC.qsort(sorted_paths as Void*, sorted_paths.size, 4, compar)
    sorted_paths.sort
  end

  class Math
    def initialize
      #
    end

    def checksum(path, crypto)
      bufsize = 4096
      if crypto == LocalCrypto::Algorithm::MD5
        digest = LocalCrypto::MD5Delegate.new bufsize
      else
        digest = LocalCrypto::MD4Impl.new bufsize
      end
      File.open(path, "r")  do |file_in|
        buffer = Slice(UInt8).new bufsize
        complete = false
        until complete
          count = file_in.read buffer
          if count == bufsize
            digest.update buffer
          else
            partial_buffer = Slice(UInt8).new(count) { |i| buffer[i] }
            digest.update partial_buffer
            complete = true
          end
        end
      end
      digest.finish
      digest.to_s
    end

  end
end
