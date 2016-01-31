@[Link("s3helper")]
lib LibS3
  fun aws_set_key(key: UInt8*)
  fun aws_set_keyid(key: UInt8*)
  fun aws_set_accesscontrol(accesscontrol: UInt8*)
  fun aws_set_mimetype(mimetype: UInt8*)
  fun getStringToSign(date: UInt8**, method: UInt8*, bucket: UInt8*, file: UInt8*): UInt8*
  fun cr_aws_put(date: UInt8*, signature: UInt8*, resource_name: UInt8*, resource_path: UInt8*, bucket: UInt8*)
end

require "inifile"
require "http"

module S3Util extend self

  class Actor
    S3Host = "s3.amazonaws.com"

    def initialize(auth_file_name)
      ini = IniFile.load(File.read FileUtil.canonical_path auth_file_name)
      @aws_keyid = ini["s3"]["id"]
      @aws_bucket = ini["s3"]["bucket"]
      @aws_access_control = "public-read"
      @aws_mime_type = "text/plain"
      LibS3.aws_set_key(ini["s3"]["secret"].to_unsafe)
      LibS3.aws_set_keyid(@aws_keyid.to_unsafe)
      LibS3.aws_set_accesscontrol(@aws_access_control)
      LibS3.aws_set_mimetype(@aws_mime_type)

      c_put("README.md", "README.md")
    end

    # TODO I will need to use CURLOPT_READFUNCTION no matter what:
    # it will be necessary when invoking Compress's methods
    def copy(source_path, dest_path, compress?)
    end

    private def compress_copy(source_path, dest_path)
    end

    private def expand_copy(source_path, dest_path)
    end

    def preserve_copy(source_path, dest_path)
    end

    private def c_put(resource_name, resource_path)
      ref_date_ptr = Pointer(UInt8*).malloc(1)
      signature = String.new(LibS3.getStringToSign(ref_date_ptr, "PUT", @aws_bucket, resource_name))
      ref_date_str = String.new ref_date_ptr.value
      LibS3.cr_aws_put(ref_date_str, signature, resource_name, resource_path, @aws_bucket)
    end
  end
end
