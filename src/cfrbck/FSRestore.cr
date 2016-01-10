module FS
  class Restorer
    getter start_dir, output_dir, force, verbose

    def initialize(start_dir, output_dir)
      @start_dir    = FileUtil.canonical_path(start_dir)
      @output_dir   = FileUtil.canonical_path(output_dir)
      @force        = false
      @verbose      = 1
    end

    def set_force
      @force = true
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
      files     = (catalog as Hash)["files"] as Array
      symlinks  = (catalog as Hash)["symlinks"] as Array

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

    # dn:s, store_name: s. fingerprint: s, instances: A ->
    # instance_path :s, root: s, mtime: s, perm: s, uid: s, gid: s
    def write_files(files)
      files.each do |entry|
        store_name = (entry as Hash)["store_name"] as String
        ((entry as Hash)["instances"] as Array).each do |instance|
          file_path = File.join(output_dir,
              FileUtil.normalized_path(
                  (instance as Hash)["root"] as String,
                  (instance as Hash)["instance_path"] as String))
          FileUtil.copy(File.join(start_dir, store_name), file_path)
          FileUtil.chmod(file_path, ((instance as Hash)["perm"] as String).to_i, force)
          FileUtil.chown(file_path,
              ((instance as Hash)["uid"] as String).to_i,
              ((instance as Hash)["gid"] as String).to_i,
              force)
        end
      end
    end

    # symlinkL: source, instances[0]{target_path:s, root:s, perm, uid, gid}
    def write_symlinks(symlinks)
      symlinks.each do |entry|
        symlink_name = (entry as Hash)["symlink"] as String
        root         = (entry as Hash)["root"] as String
        source_path = FileUtil.normalized_path(root, symlink_name)
        ((entry as Hash)["instances"] as Array).each do |instance|
          file_path = File.join(output_dir, source_path)
          FileUtil.symlink(
              (instance as Hash)["target_path"] as String,
              file_path,
              force)
        end
      end
    end

    def read_metadata
      YAML.load(File.read(File.join(start_dir, "catalog.yml")))
    end
  end
end
