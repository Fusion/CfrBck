module FS
  class Info
    def initialize(start_dir)
      if File.exists? start_dir
        read_metadata start_dir
      end
    end

    def read_metadata(data_dir)
      d = Dir.new data_dir
      matches = [] of String
      d.each do |fe|
        fe.match(/catalog([0-9]+)\.yml/) do |match|
          matches << fe.to_s
        end
      end
      paths = FileUtil.sort_paths(matches)
      paths.each do |path|
        # Naive reader so that we do not read the whole catalog files
        puts "\n#{path}:"
        files_, dirs_, info_ = 0, 0,  false
        File.open(File.join(data_dir, path), "r")  do |meta_file|
          buffer = Slice(UInt8).new(4096)
          count = meta_file.read(buffer)
          if count > 0
            String.new(buffer).each_line do |line|
              if line.starts_with? "  date:"
                info_ = true
                whn = line[8..-1].rstrip
                puts "    Created on #{whn}"
              elsif line.starts_with? "  hierarchy:"
                dirs_ = line[13..-1].rstrip
              elsif line.starts_with? "  files:"
                files_ = line[9..-1].rstrip
              elsif line.starts_with? "  artefacts:"
                artefacts_ = line[13..-1].rstrip
                puts "    #{files_} files dedupped to #{artefacts_} artefacts in #{dirs_} directories."
              end
              break if line.starts_with? "  symlinks:"
            end
          end
        end
        puts "    No information" if !info_
      end
      puts ""
    end
  end
end
