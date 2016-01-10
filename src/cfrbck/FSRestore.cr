module FS
  class Restorer
    getter start_dir, output_dir, verbose

    def initialize(start_dir, output_dir)
      @start_dir    = FileUtil.canonical_path(start_dir)
      @output_dir   = FileUtil.canonical_path(output_dir)
      @verbose      = 1
    end

    def verbose=(level)
      @verbose = level
    end

    def prepare
      if !File.exists?(output_dir)
        Dir.mkdir(output_dir)
      end
    end

    def start
      catalog = read_metadata
      hierarchy = (catalog as Hash)["hierarchy"] as Array
      files     = (catalog as Hash)["files"]
      symlinks  = (catalog as Hash)["symlinks"]
      write_hierarchy(hierarchy)
      write_files(files)
      write_symlinks(symlinks)
    end

    def write_hierarchy(hierarchy)
      hierarchy.each do |entry|
        ((entry as Hash)["instances"] as Array).each do |instance|
          dir_path = File.join(output_dir,
              FileUtil.normalized_path(
                  (instance as Hash)["root"] as String,
                  (instance as Hash)["instance_path"] as String))
          if !File.exists?(dir_path)
            Dir.mkdir_p(dir_path, ((instance as Hash)["perm"] as String).to_i)
          end
        end
      end
    end

    def write_files(files)
    end

    def write_symlinks(symlinks)
    end

    def read_metadata
      YAML.load(File.read(File.join(start_dir, "catalog.yml")))
    end
  end
end
