module FS
	class Entity
		getter entries

		enum Type
			File
			SymLink
		end

		def initialize(@entity_type, first_entry)
			@entries = [first_entry as BackupableInstance]
		end

		def push(entry)
			@entries << entry as BackupableInstance
		end

		def entries=(values)
			@entries = values
		end

		def store_name=(name)
			@store_name = name
		end

		def count
			@entries.size
		end

		def dump
			entries.each do |entry|
				puts "  - #{entry.to_s}"
			end
		end

		def to_yaml(key, yaml : YAML::Generator)
			case @entity_type
			when Type::File
				yaml.nl("- dn: ")
				key.to_yaml(yaml)
				yaml.nl("  store_name: ")
				@store_name.to_yaml(yaml)
			when Type::SymLink
				yaml.nl("- symlink: ")
				key.to_yaml(yaml)
			end
			yaml.indented do
				yaml.nl
				yaml << "instances:"
				String.build do |str|
					entries.each do |entry|
						(entry as BackupableInstance).to_yaml(key, yaml)
					end
				end
			end
		end
	end
end
