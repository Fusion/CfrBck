require "dir"
require "progress"

module FS
	class Traverser
		def initialize(start_dir, output_dir)
			@start_dir = start_dir
			@output_dir = output_dir
			@files = Meta.new
			@symlinks = Meta.new
			@stored_items = {} of String => String
			@ignore_dates = false
			@verbose = 1
		end

		private def start_dir
			@start_dir
		end

		private def output_dir
			@output_dir
		end

		private def files
			@files
		end

		private def symlinks
			@symlinks
		end

		private def ignore_dates
			@ignore_dates
		end

		def set_ignore_dates
			@ignore_dates = true
		end

		private def verbose
			@verbose
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

		# TODO If I used actual unique ids, then I could run multiple backups
		# in parallel with same output directory
		# Alternatively I could start threading this code.
		private def write_files
			puts "Copying unique files..." if verbose > 0

			uniqueid = 0

			sp = Util::SimpleProgress.new files.count
			onep = files.count / 100.0
			onep = 1 if onep < 1
			next_tick = onep
			processed_count = 0
			bar = ProgressBar.new
			bar.total = 100

			files.each do |key, value|
				index = uniqueid.to_s
				uniqueid += 1
				#puts "+ #{uniqueid} -> #{key}:"
				#puts "- #{item}"
				# we are going to store first file, regardless
				# of list size
				item = value.entries.first.file_path
				#puts "Copy #{item} to #{File.join(output_dir, uniqueid.to_s)}"
				FileUtil.copy(item, File.join(output_dir, uniqueid.to_s))
				processed_count += value.count
				if processed_count > next_tick
					next_tick += onep
					bar.inc if verbose == 1
				end
			end
			bar.done if verbose == 1
		end

		private def write_symlinks
			puts "Storing symbolink links..." if verbose > 0

			onep = symlinks.count / 100.0
			onep = 1 if onep < 1
			next_tick = onep
			processed_count = 0
			bar = ProgressBar.new
			bar.total = 100

			symlinks.each do |key, value|
				item = (value.entries.first as SymLinkInstance).target_path
				processed_count += 1
				if processed_count > next_tick
					next_tick += onep
					bar.inc if verbose == 1
				end
			end
			bar.done if verbose == 1
		end

		private def write_metadata
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
					files.count_inc
				else
					real_name = FileUtil.readlink(file_path)
					obj = SymLinkInstance.new(file_path, real_name, f_stat.perm, f_stat.uid, f_stat.gid)
					symlinks["#{file_path}"] = Entity.new obj
					symlinks.count_inc
				end
			else
				# TODO non existent file... e.g. broken symlink
			end
			name
		end

		class Meta < Hash(String, Entity)
			def initialize
				super
				@count = 0
			end

			def count
				@count
			end

			def count=(other)
				@count = other
			end

			def count_inc
				@count += 1
			end
		end

		class Entity
			def initialize(first_entry)
				@entries = [first_entry as BackupableInstance]
				@count = 1
			end

			def push(entry)
				@entries << entry as BackupableInstance
				@count += 1
			end

			def dump
				entries.each do |entry|
					puts "  - #{entry.to_s}"
				end
			end

			def entries
				@entries
			end

			def count
				@count
			end
		end

		class BackupableInstance
			def initialize(file_path, perm, uid, gid)
				@file_path = file_path
				@file_perm = perm
				@file_uid = uid
				@file_gid = gid
			end

			def file_path
				@file_path
			end
		end

		class FileInstance < BackupableInstance
			def initialize(file_path, perm, uid, gid)
				super(file_path, perm, uid, gid)
			end

			def to_s
				":#{@file_path}:#{@file_perm}:#{@file_uid}:#{@file_gid}"
			end
		end

		class SymLinkInstance < BackupableInstance
			def initialize(file_path, target_path, perm, uid, gid)
				super(file_path, perm, uid, gid)
				@target_path = target_path
			end

			def target_path
				@target_path
			end

			def to_s
				":#{@file_path}->#{@target_path}:#{@file_perm}:#{@file_uid}:#{@file_gid}"
			end
		end
	end
end
