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
  enum Action
    PRESERVE
    COMPRESS
    EXPAND
  end

  def get_actor(config)
    case config.platform_name
    when "local"
      LocalUtil::Actor.new config
    when "s3"
      S3Util::Actor.new config
    else
      raise FileUtilException.new "Unknown platform type"
    end
  end

  def readlink(link_path)
    target_path_ptr = Pointer(UInt8).malloc(1025)
    read_count = LibC.readlink(link_path, target_path_ptr, 1024)
    String.new(target_path_ptr, read_count)
  end

  def symlink(target, link_path, force = false)
    if 0 != LibC.symlink(target, link_path)
      raise FileUtilException.new "Unable to create symbolic link #{target} for #{link_path}" unless force
    end
  end

  def chown(file_path, owner, group, force = false)
    if 0 != LibC.chown(file_path, owner, group)
      raise FileUtilException.new "Unable to change ownerhsip to #{owner}:#{group} for file #{file_path}" unless force
    end
  end

  def chmod(file_path, mode, force = false)
    if 0 != LibC.chmod(file_path, mode)
      raise FileUtilException.new "Unable to change mode to #{mode} for file #{file_path}" unless force
    end
  end

  def canonical_path(path)
    File.expand_path(path)
  end

  def normalized_path(canon, path)
    canonp = File.join(canon, "")
    if !path.starts_with? canon
      raise FileUtilException.new "Attempt to normalize [#{path}] based on [#{canonp}] is not legal."
    end
    path.sub(canonp, "")
  end

  def sort_paths(paths : Array(String))
    sorted_paths = paths.clone
    #compar = ->(x : Void*, y : Void*) do (x as String*).value < (y as String*).value ? 1 : -1 end
    #LibC.qsort(sorted_paths as Void*, sorted_paths.size, 4, compar)
    sorted_paths.sort
  end

  def prepare(location : String)
    if !File.exists?(location)
      Dir.mkdir(location)
    end
  end

  def retrieve_catalog(location : String, new_catalog_id : UInt32): RetrieveCatalogResult
    ref_catalog = ""

    d = Dir.new location
    # not using glob() as I do not wish to change directory
    d.each do |fe|
      fe.match(/catalog([0-9]+)\.yml/) do |match|
        if match[1].to_i >= new_catalog_id
          new_catalog_id = 1 + match[1].to_i
          ref_catalog = fe.to_s
        end
      end
    end

    RetrieveCatalogResult.new ref_catalog, new_catalog_id
  end

  def write_catalog(location : String, new_catalog_id : UInt32, caller)
    path = catalog_path(location, new_catalog_id)
    File.open(path, "w") { |f| YAML.dump(caller, f) }
    File.size(path)
  end

  def catalog_path(location, catalog_id)
    File.join(location, catalog_name catalog_id)
  end

  def catalog_name(catalog_id)
    "catalog#{catalog_id.to_s}.yml"
  end

  class FileUtilException < Exception
  end

  class FileCompressionException < FileUtilException
  end

  record RetrieveCatalogResult, ref_catalog, new_catalog_id do
    def new_catalog_id_u32
      UInt32.new new_catalog_id
    end
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
