# This a a dedupping backup tool.

# First, we go through all the files found under a common root directory;
# we will create a table of files that are deemed "same" i.e. with:
# 1.a. same size, modification date, name
# 1.b. or same size and name (testing purpose only! seriously!)
# 2. same name, size and hash -- there is still potential for false positives
# Not inmplemented and not sure necessary:
# -2
#
# TODO
# - Come up with better name!
# - Multiple roots
# - Exclude @filename
# - Merged catalogs to avoid restoring multiple instances
# - Vacuum command to remove non-referenced (by catalogs) files

require "option_parser"
require "./cfrbck/*"

module Cfrbck
  enum Action
    Undef
    Backup
    Restore
  end

  start_dir      = ""
  output_dir     = ""
  ignore_dates   = false
  fingerprint    = false
  compress       = false
  force          = false
  dry_run        = false
  excluded       = [] of Regex
  verbose_str    = "1"
  recheck_str    = "1"
  desired_action = Action::Undef

  proceed = true

  begin
    OptionParser.parse! do |parser|
      parser.banner = "Usage: cfrbck [option 1] ... [option n] <backup|restore>"
      parser.separator("\nA reasonably good compromise: -d -r 1\nTo perform incremental backups: -d -r 1 -p\n\nExamples:\n\ncfrbck -d -r 1 -p -s test backup\ncfrbck -d -r 1 -s bck -o rst restore\n")
      parser.on("-s dir", "--start=dir", "Starting directory (default=.)") { |dir| start_dir = dir }
      parser.on("-o dir", "--output=dir", "Backup directory (default=bck)") { |dir| output_dir = dir }
      parser.on("-d", "--ignore-dates", "Ignore dates") { ignore_dates = true }
      parser.on("-r level", "--recheck=level", "Recheck (0=no, 1=hash, 2=tbd!)") { |level| recheck_str = level }
      parser.on("-p", "--fingerprint", "Compute Fingerprint") { fingerprint = true }
      parser.on("-z", "--compress", "Compress artefacts (backup)") { compress = true }
      parser.on("-x pattern", "--exclude=pattern", "Exclude files matching pattern (backup)") { |pattern| excluded << Regex.new pattern }
      parser.on("-f", "--force", "Force continue on failure (restore)") { force = true }
      parser.on("--dry-run", "Dry run (no operation will be performed)") { dry_run = true }
      parser.on("-v level", "--verbose=level", "Verbose (0=quiet)") { |level| verbose_str = level }
      parser.on("-h", "--help", "Display this text") { proceed = false; puts parser }
      parser.unknown_args do |arg|
        if arg.size > 0
          if arg[0] == "backup"
            if output_dir == ""
              output_dir = "bck"
            end
            desired_action = Action::Backup
          elsif arg[0] == "restore"
            if output_dir == ""
              output_dir = "rst"
            end
            desired_action = Action::Restore
          end
        end
      end
    end
  rescue ex: OptionParser::InvalidOption
    proceed = false
    puts "#{ex}"
  end

  if proceed
    if start_dir == ""
      proceed = false
      puts "Usage information: cfrbck -h"
    elsif desired_action == Action::Undef
      puts desired_action.value
      proceed = false
      puts "Possible actions: backup|restore"
    end
  end

  if proceed
    verbose = verbose_str.to_i
    recheck = recheck_str.to_i

    if desired_action == Action::Backup
      traverser = FS::Traverser.new(start_dir, output_dir)
      if verbose > 1
        puts "(verbose output level: #{verbose})"
        traverser.verbose = verbose
      end
      if ignore_dates
        if verbose > 1
          puts "(ignoring dates)"
        end
        traverser.set_ignore_dates
      end
      if fingerprint
        if verbose > 1
          puts "(generating fingerprints)"
        end
        traverser.set_fingerprint
      end
      if compress
        if verbose > 1
          puts "(compressing artefacts)"
        end
        traverser.set_compress
      end
      if verbose > 1
        puts "(recheck level = #{recheck_str})"
      end
      traverser.recheck = recheck
      traverser.excluded = excluded
      if dry_run
        if verbose > 0
          puts "Dry run!"
        end
        traverser.set_dry_run
      end
      if verbose > 0
        puts "start_dir  = #{start_dir}"
        puts "output_dir = #{output_dir}"
      end

      traverser.prepare
      traverser.start
      traverser.dump_entities if verbose > 2

    else # RESTORE
      restorer = FS::Restorer.new(start_dir, output_dir)
      if verbose > 1
        puts "(verbose output level: #{verbose})"
        restorer.verbose = verbose
      end
      if force
        if verbose > 1
          puts "(force continue)"
        end
        restorer.set_force
      end
      if dry_run
        if verbose > 0
          puts "Dry run!"
        end
        restorer.set_dry_run
      end

      restorer.prepare
      restorer.start

    end
  end
end
