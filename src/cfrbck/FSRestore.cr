module FS
  class Restorer
    getter start_dir, output_dir, verbose

    def initialize(@start_dir, @output_dir)
      @verbose = 1
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
      files    = (catalog as Hash)["files"]
      symlinks = (catalog as Hash)["symlinks"]
      write_files(files)
      write_symlinks(symlinks)
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
