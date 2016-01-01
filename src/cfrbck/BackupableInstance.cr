module FS
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

		def to_yaml(yaml : YAML::Generator)
			to_yaml("", yaml)
		end

		def to_yaml(key, yaml : YAML::Generator)
			raise "Please override to_yaml!"
		end
	end

	class FileInstance < BackupableInstance
		def initialize(file_path, perm, uid, gid)
			super(file_path, perm, uid, gid)
		end

		def to_s
			":#{@file_path}:#{@file_perm}:#{@file_uid}:#{@file_gid}"
		end

		def to_yaml(key, yaml : YAML::Generator)
			yaml.nl("- file: ")
			key.to_yaml(yaml)
			yaml.nl("  instance_path: ")
			@file_path.to_yaml(yaml)
			yaml.nl("  perm: ")
			@file_perm.to_yaml(yaml)
			yaml.nl("  uid: ")
			@file_uid.to_yaml(yaml)
			yaml.nl("  gid: ")
			@file_gid.to_yaml(yaml)
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

		def to_yaml(key, yaml : YAML::Generator)
			yaml.nl("- symlink: ")
			key.to_yaml(yaml)
			yaml.nl("  target_path: ")
			@target_path.to_yaml(yaml)
			yaml.nl("  perm: ")
			@file_perm.to_yaml(yaml)
			yaml.nl("  uid: ")
			@file_uid.to_yaml(yaml)
			yaml.nl("  gid: ")
			@file_gid.to_yaml(yaml)
		end
	end
end
