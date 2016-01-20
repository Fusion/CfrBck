module FS
  class MetaContainer
    getter hierarchy, files, symlinks

    def initialize
      @hierarchy = Meta.new
      @files     = Meta.new
      @symlinks  = Meta.new
    end
  end
end
