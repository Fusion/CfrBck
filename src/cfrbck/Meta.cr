module FS
  class Meta < Hash(String, Entity)
		def initialize
			super
		end

		def count
			total = 0
      each do |key, entity|
        total += entity.count
      end
      total
		end

		def to_yaml(yaml : YAML::Generator)
			each do |key, entity|
				entity.to_yaml(key, yaml)
			end
		end
	end
end
