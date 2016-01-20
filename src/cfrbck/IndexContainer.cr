module FS
  class IndexContainer
    getter hierarchy, files, symlinks

    def initialize
      @hierarchy = {} of String => Hash(String, String)
      @files     = {} of String => Hash(String, String)
      @symlinks  = {} of String => Hash(String, String)
    end
  end
end
