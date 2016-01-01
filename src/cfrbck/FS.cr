require "dir"
require "yaml"
require "progress"

module FS
	class Traverser

		getter start_dir, output_dir, files, symlinks, ignore_dates, recheck, verbose

		def initialize(start_dir, output_dir)
			@start_dir = start_dir
			@output_dir = output_dir
			@files = Meta.new
			@symlinks = Meta.new
			@stored_items = {} of String => String
			@ignore_dates = false
			@recheck = 1
			@verbose = 1
		end

		def set_ignore_dates
			@ignore_dates = true
		end

		def recheck=(level)
			@recheck = level
		end

		def verbose=(level)
			@verbose = level
		end

		def dump_entities
			puts "* Dumping content of files:"
			files.each do |key, value|
				puts "+ #{key}:"
				value.dump
			end
			puts "* Dumping symlinks:"
			symlinks.each do |key, value|
				puts "+ #{key}:#{value}"
			end
		end

		def prepare
			if !File.exists?(output_dir)
				Dir.mkdir(output_dir)
			end
		end

		def start
			puts "Compiling file list including dups..." if verbose > 0
			puts "[#{start_dir}]" if verbose > 1
			run_dir(1,start_dir)
			if recheck > 0
				recheck_run_dir(recheck)
			end

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
				padding = " " * depth
				if File.directory?(fe_path)
					puts "#{padding}[#{fe}]" if verbose > 1
					run_dir(depth+1,fe_path)
				else
					res = check name: fe.to_s, file_path: fe_path
					puts "#{padding}#{res}" if verbose > 1
				end
			end
		end

		private def recheck_run_dir(recheck)
			puts "Double checking..."
			diff_files = Meta.new
			files.each do |key, value|
				if value.entries.size < 2
					next
				end
				#puts "For #{key} original value: #{(value.entries.first as BackupableInstance).file_path}"
				reference_checksum = get_file_checksum((value.entries.first as BackupableInstance).file_path)
				iter = value.entries.each
				new_array = [iter.next as BackupableInstance] # skip 1st entry
				item = iter.next
				until item == Iterator::Stop::INSTANCE
					#puts "           found potential dup: #{(item as BackupableInstance).file_path}"
					file_checksum = get_file_checksum((item as BackupableInstance).file_path)
					if file_checksum != reference_checksum
						index = file_checksum + "::" + key
						if diff_files.has_key?(index)
							diff_files[index].push item
						else
							diff_files[index] = Entity.new item
						end
						#puts "*** In fact, it WAS a fake dup!"
					else
						new_array << item as BackupableInstance
						# noop
						#puts "+cool: #{reference_checksum} (#{(value.entries.first as BackupableInstance).file_path}) v. #{file_checksum} (#{(item as BackupableInstance).file_path})"
					end
					item  = iter.next
				end
				if new_array.size != value.entries.size
					value.entries = new_array
				end
			end
			if diff_files.size > 0
				# Merge in place...ewww!
				@files.merge!(diff_files)
			end
		end

		private def get_file_checksum(file_path)
				math = FileUtil::Math.new
				math.checksum(file_path)
		end

		# TODO If I used actual unique ids, then I could run multiple backups
		# in parallel with same output directory
		# Alternatively I could start threading this code.
		private def write_files
			files_count = files.count
			puts "Copying #{files.size} unique files (for a total of #{files_count} file nodes)..." if verbose > 0

			uniqueid = 0

			sp = Util::SimpleProgress.new files_count

			files.each do |key, value|
				index = uniqueid.to_s
				uniqueid += 1
				# we are going to store first file, regardless
				# of list size
				item = value.entries.first.file_path
				FileUtil.copy(item, File.join(output_dir, uniqueid.to_s))
				sp.update value.count if verbose == 1
			end

			sp.done if verbose == 1
		end

		private def write_symlinks
			puts "Storing #{symlinks.size} symbolink links..." if verbose > 0

			sp = Util::SimpleProgress.new symlinks.size

			symlinks.each do |key, value|
				item = (value.entries.first as SymLinkInstance).target_path
				sp.update 1 if verbose == 1
			end

			sp.done if verbose == 1
		end

		private def write_metadata
			File.open("bogus.yml", "w") { |f| YAML.dump(self, f) }
		end

		private def check(name="", file_path="")
			if File.exists?(file_path)
				f_stat = File.lstat(file_path)
				if ! f_stat.symlink?
					if ignore_dates
						index = f_stat.size.to_s + "::*::" + name
					else
						index = f_stat.size.to_s + "::" + f_stat.mtime.to_s + "::" + name
					end
					obj = FileInstance.new(file_path, f_stat.perm, f_stat.uid, f_stat.gid)
					if files.has_key?(index)
						files[index].push obj
					else
						files[index] = Entity.new obj
					end
				else
					real_name = FileUtil.readlink(file_path)
					obj = SymLinkInstance.new(file_path, real_name, f_stat.perm, f_stat.uid, f_stat.gid)
					symlinks["#{file_path}"] = Entity.new obj
				end
			else
				# TODO non existent file... e.g. broken symlink
			end
			name
		end

		def to_yaml(yaml : YAML::Generator)
			yaml.nl
			yaml << "symlinks:"
			yaml.indented do
				symlinks.to_yaml(yaml)
			end
			yaml << "files:"
			yaml.indented do
				files.to_yaml(yaml)
			end
		end

	end
end