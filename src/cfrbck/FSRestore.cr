module FS
  class Restorer
    getter start_dir, output_dir, catalog_name, platform_name,
        force, dry_run, verbose

    def initialize(config)
      @start_dir     = FileUtil.canonical_path(config.start_dir)
      @output_dir    = FileUtil.canonical_path(config.output_dir)
      @file_util     = FileUtil.get_actor(config)
      @catalog_name  = ""
      @platform_name = ""
      @force         = false
      @dry_run       = false
      @verbose       = 1
    end

    def catalog=(name)
      @catalog_name = name
    end

    def platform=(name)
      @platform_name = name
    end

    def set_force
      @force = true
    end

    def set_dry_run
      @dry_run = true
    end

    def verbose=(level)
      @verbose = level
    end

    def prepare
      if !dry_run
        if !File.exists?(output_dir)
          Dir.mkdir(output_dir)
        end
      end
    end

    def start
      catalog   = read_metadata
      hierarchy = (catalog as Hash)["hierarchy"] as Array
      files     = (catalog as Hash)["files"] as Array
      symlinks  = (catalog as Hash)["symlinks"] as Array

      write_hierarchy(hierarchy)
      write_files(files)
      write_symlinks(symlinks)
    end

    def write_hierarchy(hierarchy)
      puts "Re building hierarchy..." if verbose > 0

      sp = Util::SimpleProgress.new hierarchy.size

      hierarchy.each do |entry|
        ((entry as Hash)["instances"] as Array).each do |instance|
          dir_path = File.join(output_dir,
              FileUtil.normalized_path(
                  (instance as Hash)["root"] as String,
                  (instance as Hash)["instance_path"] as String))
          if !dry_run
            if !File.exists?(dir_path)
              Dir.mkdir(dir_path, ((instance as Hash)["perm"] as String).to_i)
            end
          end
        end
        sp.update 1 if verbose == 1
      end

      sp.done if verbose == 1
    end

    # dn:s, store_name: s. fingerprint: s, instances: A ->
    # instance_path :s, root: s, mtime: s, perm: s, uid: s, gid: s
    def write_files(files)
      puts "Restoring #{files.size} dedupped files..." if verbose > 0

      sp = Util::SimpleProgress.new files.size

      files.each do |entry|
        store_name = (entry as Hash)["store_name"] as String
        ((entry as Hash)["instances"] as Array).each do |instance|
          file_path = File.join(output_dir,
              FileUtil.normalized_path(
                  (instance as Hash)["root"] as String,
                  (instance as Hash)["instance_path"] as String))
          if !dry_run
            compress = store_name.ends_with?("-z") ?
                FileUtil::Action::EXPAND : FileUtil::Action::PRESERVE
            @file_util.copy(
                File.join(start_dir, store_name),
                ResourcePath.new(store_name, file_path),
                compress)
            FileUtil.chmod(file_path,
                ((instance as Hash)["perm"] as String).to_i,
                force)
            FileUtil.chown(file_path,
                ((instance as Hash)["uid"] as String).to_i,
                ((instance as Hash)["gid"] as String).to_i,
                force)
          end
        end
        sp.update 1 if verbose == 1
      end

      sp.done if verbose == 1
    end

    # symlinkL: source, instances[0]{target_path:s, root:s, perm, uid, gid}
    def write_symlinks(symlinks)
      puts "Restoring #{symlinks.size} symbolink links..." if verbose > 0

      sp = Util::SimpleProgress.new symlinks.size

      symlinks.each do |entry|
        symlink_name = (entry as Hash)["symlink"] as String
        root         = (entry as Hash)["root"] as String
        source_path = FileUtil.normalized_path(root, symlink_name)
        ((entry as Hash)["instances"] as Array).each do |instance|
          file_path = File.join(output_dir, source_path)
          if !dry_run
            FileUtil.symlink(
                (instance as Hash)["target_path"] as String,
                file_path,
                force)
          end
        end
        sp.update 1 if verbose == 1
      end

      sp.done if verbose == 1
    end

    def read_metadata
      if catalog_name == ""
        ref_catalog = ""
        d = Dir.new start_dir
        # not using glob() as I do not wish to change directory
        max_catalog_id = 1
        d.each do |fe|
          fe.match(/catalog([0-9]+)\.yml/) do |match|
            if match[1].to_i >= max_catalog_id
              max_catalog_id = 1 + match[1].to_i
              ref_catalog = fe.to_s
            end
          end
        end
      else
        ref_catalog = catalog_name
      end

      if ref_catalog != ""
        YAML.load(File.read(File.join(start_dir, ref_catalog)))
      end
    end
  end
end
