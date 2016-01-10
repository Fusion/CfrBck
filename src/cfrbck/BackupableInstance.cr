module FS
  class BackupableInstance
    getter file_path

    def initialize(@file_path, @root, @file_perm, @file_uid, @file_gid)
    end

    def to_yaml(yaml : YAML::Generator)
      to_yaml("", yaml)
    end

    def to_yaml(key, yaml : YAML::Generator)
      raise "Please override to_yaml!"
    end
  end

  class FileInstance < BackupableInstance
    def initialize(file_path, root, @mtime, perm, uid, gid)
      super(file_path, root, perm, uid, gid)
    end

    def to_s
      ":#{@file_path}:#{@file_perm}:#{@file_uid}:#{@file_gid}"
    end

    def to_yaml(key, yaml : YAML::Generator)
      yaml.nl("- instance_path: ")
      @file_path.to_yaml(yaml)
      yaml.nl("  root: ")
      @root.to_yaml(yaml)
      yaml.nl("  mtime: ")
      @mtime.to_yaml(yaml)
      yaml.nl("  perm: ")
      @file_perm.to_yaml(yaml)
      yaml.nl("  uid: ")
      @file_uid.to_yaml(yaml)
      yaml.nl("  gid: ")
      @file_gid.to_yaml(yaml)
    end
  end

  class SymLinkInstance < BackupableInstance
    getter target_path

    def initialize(file_path, root, @target_path, perm, uid, gid)
      super(file_path, root, perm, uid, gid)
    end

    def to_s
      ":#{@file_path}->#{@target_path}:#{@file_perm}:#{@file_uid}:#{@file_gid}"
    end

    def to_yaml(key, yaml : YAML::Generator)
      yaml.nl("- target_path: ")
      @target_path.to_yaml(yaml)
      yaml.nl("  root: ")
      @root.to_yaml(yaml)
      yaml.nl("  perm: ")
      @file_perm.to_yaml(yaml)
      yaml.nl("  uid: ")
      @file_uid.to_yaml(yaml)
      yaml.nl("  gid: ")
      @file_gid.to_yaml(yaml)
    end
  end
end
