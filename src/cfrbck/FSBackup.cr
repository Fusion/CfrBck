require "dir"
require "yaml"
require "secure_random"
require "progress"

module FS
  class Traverser
    getter start_dir, output_dir, meta_container, ignore_dates,
        fingerprint, excluded, recheck, dry_run, verbose

    def initialize(start_dir, output_dir)
      @start_dir      = FileUtil.canonical_path(start_dir)
      @output_dir     = FileUtil.canonical_path(output_dir)
      @meta_container = MetaContainer.new
      @stored_items   = {} of String => String
      @ignore_dates   = false
      @fingerprint    = false
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
        uniqueid = SecureRandom.uuid
        store_name = uniqueid.to_s

        # we are going to store first file, regardless
        # of list size
        item = value.entries.first.file_path
        value.store_name = store_name
        if !dry_run
          FileUtil.copy(item, File.join(output_dir, store_name))
        end
        # fix fingerprint for files that do not have that computed yet
        if fingerprint && value.fingerprint == Entity::EmptyFingerprint
          value.fingerprint = get_file_checksum(item)
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

    private def write_metadata
      if !dry_run
        File.open(File.join(output_dir, "catalog.yml"), "w") { |f| YAML.dump(self, f) }
      end
    end

    private def check_file(name="", file_path="")
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
        # TODO non existent file... e.g. broken symlink
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
