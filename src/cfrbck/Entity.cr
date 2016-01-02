module FS
	class Entity
		getter entries

		def initialize(first_entry)
			@entries = [first_entry as BackupableInstance]
		end

		def push(entry)
			@entries << entry as BackupableInstance
		end

		def entries=(values)
			@entries = values
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
			String.build do |str|
				entries.each do |entry|
					(entry as BackupableInstance).to_yaml(key, yaml)
				end
			end
		end
	end
end
