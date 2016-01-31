module FileUtil extend self
  class Config
    getter  start_dir,
            output_dir,
            platform_name,
            auth_file_name

    def initialize
      # Help Crystal realize that these are never nil
      @start_dir = ""
      @output_dir = ""
      @platform_name = ""
      @auth_file_name = ""
    end

    def start_dir=(start_dir)
      @start_dir = start_dir
    end

    def output_dir=(output_dir)
      @output_dir = output_dir
    end

    def platform_name=(platform)
      @platform_name = platform
    end

    def auth_file_name=(name)
      @auth_file_name = name
    end
  end
end
