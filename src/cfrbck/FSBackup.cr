require "dir"
require "yaml"
require "secure_random"
require "progress"

module FS
  class Traverser
    getter start_dir, output_dir, meta_container, ignore_dates,
        fingerprint, compress, excluded, recheck,
        dry_run, verbose

    def initialize(start_dir, output_dir)
      @start_dir      = FileUtil.canonical_path(start_dir)
      @output_dir     = FileUtil.canonical_path(output_dir)
      @meta_container = MetaContainer.new
      @comp_container = IndexContainer.new
      @new_catalog_id = 1
      @stored_items   = {} of String => String
      @ignore_dates   = false
      @fingerprint    = false
      @compress       = false
      @dry_run        = false
      @excluded       = [] of Regex
      @recheck        = 1
      @use_md5        = true
      @verbose        = 1
    end

    def set_ignore_dates
      @ignore_dates = true
    end

    def set_fingerprint
      @fingerprint = true
    end

    def set_compress
      @compress = true
    end

    def set_dry_run
      @dry_run = true
    end

    def recheck=(level)
      @recheck = level
    end

    def excluded=(exclude_list)
      @excluded = exclude_list
    end

    def verbose=(level)
      @verbose = level
    end

    def dump_entities
      puts "* Dumping hierarchy:"
      meta_container.hierarchy.each do |key, value|
        puts "+ #{key}:#{value}"
      end
      puts "* Dumping content of files:"
      meta_container.files.each do |key, value|
        puts "+ #{key}:"
        value.dump
      end
      puts "* Dumping symlinks:"
      meta_container.symlinks.each do |key, value|
        puts "+ #{key}:#{value}"
      end
    end

    def prepare
      if !dry_run
        if !File.exists?(output_dir)
          Dir.mkdir(output_dir)
        end
      end

      read_metadata
    end

    def start
      puts "Compiling file list including dups..." if verbose > 0
      puts "[#{start_dir}]" if verbose > 1
      run_dir(1,start_dir)
      if recheck > 0
        recheck_run_dir(recheck)
      end

      write_hierarchy
      write_files
      write_symlinks
      write_metadata

      puts "Done." if verbose > 0
    end

    private def run_dir(depth, dir_name)
      d = Dir.new dir_name
      d.each do |fe|
        next if fe == "." || fe == ".."
        fe_path = File.join(dir_name, fe.to_s)
        if desired?(fe_path)
          padding = " " * depth
          if File.directory?(fe_path)
            puts "#{padding}[#{fe}]" if verbose > 1
            check_dir name: fe_path, dir_path: fe_path
            run_dir(depth+1,fe_path)
          else
            res = check_file name: fe.to_s, file_path: fe_path
            puts "#{padding}#{res}" if verbose > 1
          end
        else
          puts "Ignoring #{fe_path} due to exclusion pattern" if verbose > 2
        end
      end
    end

    private def desired?(path)
      !excluded.any? { |exp| exp.match(path) }
    end

    private def recheck_run_dir(recheck)
      puts "Double checking..."
      diff_files = Meta.new
      meta_container.files.each do |key, value|
        if value.entries.size < 2
          next
        end
        puts "For #{key} original value: #{(value.entries.first as BackupableInstance).file_path}" if verbose > 2
        reference_checksum = get_file_checksum((value.entries.first as BackupableInstance).file_path)
        value.fingerprint = reference_checksum if fingerprint # patch with that fingerprint
        iter = value.entries.each
        new_array = [iter.next as BackupableInstance] # skip 1st entry
        item = iter.next
        until item == Iterator::Stop::INSTANCE
          puts "          found potential dup: #{(item as BackupableInstance).file_path}" if verbose > 2
          file_checksum = get_file_checksum((item as BackupableInstance).file_path)
          if file_checksum != reference_checksum
            index = file_checksum + "::" + key
            if diff_files.has_key?(index)
              diff_files[index].push item
            else
              diff_files[index] = Entity.new(Entity::Type::File, item, fingerprint ? file_checksum : Entity::EmptyFingerprint)
            end
            puts "          Fake Dup: #{reference_checksum} (#{(value.entries.first as BackupableInstance).file_path}) v. #{file_checksum} (#{(item as BackupableInstance).file_path})" if verbose > 2
          else
            new_array << item as BackupableInstance
            puts "          Confirmed Dup: #{reference_checksum} (#{(value.entries.first as BackupableInstance).file_path}) v. #{file_checksum} (#{(item as BackupableInstance).file_path})" if verbose > 2
          end
          item  = iter.next
        end
        if new_array.size != value.entries.size
          value.entries = new_array
        end
      end
      if diff_files.size > 0
        # Merge in place...ewww!
        meta_container.files.merge!(diff_files)
      end
    end

    private def get_new_artefact_id
      uniqueid = SecureRandom.uuid
      compress ? "#{uniqueid.to_s}-z" : uniqueid.to_s
    end

    private def get_file_checksum(file_path)
        math = FileUtil::Math.new
        math.checksum(file_path, LocalCrypto::Algorithm::MD5)
    end

    # Using actual unique ids, so that I could run multiple backups
    # in parallel with same output directory
    # Alternatively I could start threading this code.
    private def write_files
      files_count = meta_container.files.count
      puts "Copying #{meta_container.files.size} unique files (for a total of #{files_count} file nodes)..." if verbose > 0

      sp = Util::SimpleProgress.new files_count

      meta_container.files.each do |key, value|
        must_save_file = false

        item = value.entries.first.file_path
        # fix fingerprint for files that do not have that computed yet
        if fingerprint && value.fingerprint == Entity::EmptyFingerprint
          value.fingerprint = get_file_checksum(item)
        end

        store_name = get_new_artefact_id

        # let us compare file fingerprint
        value.entries.each do |entry|
          norm_path = FileUtil.normalized_path(
            start_dir,
            entry.file_path)
          if !@comp_container.files.has_key?(norm_path)
            must_save_file = true
          else
            prev_info = @comp_container.files[norm_path]
            if value.fingerprint != prev_info["fingerprint"]
              must_save_file = true
            else
              store_name = prev_info["store_name"]
            end
          end
        end

        # we are going to store first file, regardless
        # of list size
        value.store_name = store_name
        if must_save_file
          if !dry_run
            FileUtil.copy(
                item,
                File.join(output_dir, store_name),
                compress ? FileUtil::Action::COMPRESS : FileUtil::Action::PRESERVE)
          end
        end
        sp.update value.count if verbose == 1
      end

      sp.done if verbose == 1
    end

    # noop
    private def write_hierarchy
      puts "Memorizing #{meta_container.hierarchy.size} directories..." if verbose > 0

      sp = Util::SimpleProgress.new meta_container.hierarchy.size

      meta_container.hierarchy.each do |key, value|
        sp.update value.count if verbose == 1
      end

      sp.done if verbose == 1
    end

    # noop
    private def write_symlinks
      puts "Storing #{meta_container.symlinks.size} symbolink links..." if verbose > 0

      sp = Util::SimpleProgress.new meta_container.symlinks.size

      meta_container.symlinks.each do |key, value|
        item = (value.entries.first as SymLinkInstance).target_path
        sp.update 1 if verbose == 1
      end

      sp.done if verbose == 1
    end

    private def read_metadata
      if dry_run
        return
      end

      ref_catalog = ""
      # matches are unused in backup
      # use in restore though
      #matches = [] of String
      #paths = FileUtil.sort_paths(matches)
      #paths.each do |path|

      d = Dir.new output_dir
      # not using glob() as I do not wish to change directory
      d.each do |fe|
        fe.match(/catalog([0-9]+)\.yml/) do |match|
          if match[1].to_i >= @new_catalog_id
            @new_catalog_id = 1 + match[1].to_i
            ref_catalog = fe.to_s
          end
        end
      end

      if ref_catalog != ""
        catalog = YAML.load(File.read(File.join(output_dir, ref_catalog)))
        hierarchy = (catalog as Hash)["hierarchy"] as Array
        files     = (catalog as Hash)["files"] as Array
        symlinks  = (catalog as Hash)["symlinks"] as Array
        files.each do |entry|
          store_name = (entry as Hash)["store_name"] as String
          fingerprint = (entry as Hash)["fingerprint"] as String
          ((entry as Hash)["instances"] as Array).each do |instance|
            norm_path = FileUtil.normalized_path(
              start_dir,
              (instance as Hash)["instance_path"] as String)
            @comp_container.files[norm_path] = {
              "store_name" : store_name,
              "fingerprint": fingerprint,
              "uid": (instance as Hash)["uid"] as String,
              "gid": (instance as Hash)["gid"] as String,
              "perm": (instance as Hash)["perm"] as String,
              "mtime": (instance as Hash)["mtime"] as String
            }
          end
        end
      end
    end

    private def write_metadata
      if !dry_run
        File.open(File.join(output_dir, "catalog#{@new_catalog_id}.yml"), "w") { |f| YAML.dump(self, f) }
      end
    end

    private def check_file(name="", file_path="")
      rsh = (file_path =~ /awk/)
      if File.exists?(file_path)
        f_stat = File.lstat(file_path)
        # NOTE: mtime is what we are after. ctime would be modified in more situations
        # but we store files' attributes anyway. This may change down the road
        # when performing incremental backups as inode change may be relevant.
        if ! f_stat.symlink?
          mtime_str = f_stat.mtime.epoch.to_s
          if ignore_dates
            index = f_stat.size.to_s + "::*::" + name
          else
            index = f_stat.size.to_s + "::" + mtime_str + "::" + name
          end
          obj = FileInstance.new(file_path, @start_dir, mtime_str, f_stat.perm, f_stat.uid, f_stat.gid)
          if meta_container.files.has_key?(index)
            meta_container.files[index].push obj
          else
            meta_container.files[index] = Entity.new(Entity::Type::File, obj)
          end
        else
          real_name = FileUtil.readlink(file_path)
          obj = SymLinkInstance.new(file_path, @start_dir, real_name, f_stat.perm, f_stat.uid, f_stat.gid)
          entity = Entity.new(Entity::Type::SymLink, obj)
          entity.root = @start_dir
          meta_container.symlinks["#{file_path}"] = entity
        end
      else
        # non existent file... e.g. broken symlink
        f_stat = File.lstat(file_path)
        if f_stat.symlink?
          real_name = FileUtil.readlink(file_path)
          obj = SymLinkInstance.new(file_path, @start_dir, real_name, f_stat.perm, f_stat.uid, f_stat.gid)
          entity = Entity.new(Entity::Type::SymLink, obj)
          entity.root = @start_dir
          meta_container.symlinks["#{file_path}"] = entity
        end
      end
      name
    end

    private def check_dir(name="", dir_path="")
      if File.exists?(dir_path)
        f_stat = File.lstat(dir_path)
        mtime_str = f_stat.mtime.epoch.to_s
        obj = FileInstance.new(dir_path, @start_dir, mtime_str, f_stat.perm, f_stat.uid, f_stat.gid)
        meta_container.hierarchy["#{dir_path}"] = Entity.new(Entity::Type::Directory, obj)
      end
      name
    end

    def to_yaml(yaml : YAML::Generator)
      yaml.nl
      yaml << "meta:"
      yaml.indented do
        yaml.nl("date: ")
        Time.now.to_s.to_yaml(yaml)
        yaml.nl("epoch: ")
        Time.now.epoch.to_yaml(yaml)
        yaml.nl("directories: ")
        meta_container.hierarchy.size.to_yaml(yaml)
        yaml.nl("files: ")
        meta_container.files.count.to_yaml(yaml)
        yaml.nl("artefacts: ")
        meta_container.files.size.to_yaml(yaml)
        yaml.nl("symlinks: ")
        meta_container.symlinks.size.to_yaml(yaml)
      end
      yaml.nl
      yaml << "symlinks:"
      yaml.indented do
        meta_container.symlinks.to_yaml(yaml)
      end
      yaml.nl
      yaml << "files:"
      yaml.indented do
        meta_container.files.to_yaml(yaml)
      end
      yaml.nl
      yaml << "hierarchy:"
      yaml.indented do
        meta_container.hierarchy.to_yaml(yaml)
      end
    end

  end
end
