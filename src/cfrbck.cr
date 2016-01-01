# This a a dedupping backup tool. Or it will be some day (hopefully!)

# First, we go through all the files found under a common root directory;
# we will create a table of files that are deemed "same" i.e. with:
# 1.a. same size, modification date, name
# 1.b. or same size and name (testing purpose only! seriously!)
# 2. same name, size and hash -- there is still potential for false positives
# Not inmplemented:
# -2
# -files with different names: use hash instead of file name then check?
#
# So, what are we storing?
# For each instance of a file:
# - full path
# - mod
# - ownership
# - ext attrs?
#
# Second, we run through all these files, and for each one, we:
# 1. create a new uniqueid
# 2. store file as uniqueid
# 3.a. make a db note of uniqueid -> index(filename, etc) -> instances
# 3.b. make a db note of index(filename, etc) -> uniqueid -> instances
# 4. store metadata for future retrieval

require "option_parser"
require "./cfrbck/*"

module Cfrbck
	start_dir = "."
	output_dir = "bck"
	ignore_dates = false
	verbose_str = "1"
	recheck_str = "1"

	proceed = true

	OptionParser.parse! do |parser|
		parser.banner = "Usage: cfrbck [option 1] ... [option n]"
		parser.separator("\nA reasonably good compromise: -d -r 1\n")
		parser.on("-s dir", "--start=dir", "Starting directory (default=.)") { |dir| start_dir = dir }
		parser.on("-o dir", "--output=dir", "Backup directory (default=bck)") { |dir| output_dir = dir }
		parser.on("-d", "--ignore-dates", "Ignore dates") { ignore_dates = true }
		parser.on("-r level", "--recheck=level", "Recheck (0=no, 1=hash, 2=tbd!)") { |level| recheck_str = level }
		parser.on("-v level", "--verbose=level", "Verbose (0=quiet)") { |level| verbose_str = level }
		parser.on("-h", "--help") { proceed = false; puts parser }
	end

	if proceed
		verbose = verbose_str.to_i
		recheck = recheck_str.to_i

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
		if verbose > 1
			puts "(recheck level = #{recheck_str})"
		end
		traverser.recheck = recheck
		if verbose > 0
			puts "start_dir  = #{start_dir}"
			puts "output_dir = #{output_dir}"
		end

		traverser.prepare
		traverser.start
		traverser.dump_entities if verbose > 2
	end
end