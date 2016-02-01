@[Link("minizs3")]
lib LibMS
  fun aws_set_key(key: UInt8*)
  fun aws_set_keyid(key: UInt8*)
  fun aws_set_accesscontrol(accesscontrol: UInt8*)
  fun aws_set_mimetype(mimetype: UInt8*)
  fun getStringToSign(date: UInt8**, method: UInt8*, bucket: UInt8*, file: UInt8*): UInt8*
  fun cr_aws_put(date: UInt8*, signature: UInt8*, resource_name: UInt8*, resource_path: UInt8*, bucket: UInt8*)
  fun cr_aws_put_compress(date: UInt8*, signature: UInt8*, resource_name: UInt8*, resource_path: UInt8*, bucket: UInt8*)
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
      LibMS.aws_set_key(ini["s3"]["secret"].to_unsafe)
      LibMS.aws_set_keyid(@aws_keyid.to_unsafe)
      LibMS.aws_set_accesscontrol(@aws_access_control)
      LibMS.aws_set_mimetype(@aws_mime_type)

      c_put("README.md", "README.md")
    end

    def copy(source_path, dest_path, compress?)
    end

    private def compress_copy(source_path, dest_path)
    end

    private def expand_copy(source_path, dest_path)
    end

    def preserve_copy(source_path, dest_path)
    end

    private def c_put(resource_name, resource_path)
      date, signature = date_and_signature resource_name
      #LibMS.cr_aws_put(date, signature, resource_name, resource_path, @aws_bucket)
      LibMS.cr_aws_put_compress(date, signature, resource_name, resource_path, @aws_bucket)
    end

    private def date_and_signature(resource)
      ref_date_ptr = Pointer(UInt8*).malloc(1)
      signature = String.new(LibMS.getStringToSign(ref_date_ptr, "PUT", @aws_bucket, resource))
      ref_date_str = String.new ref_date_ptr.value
      [ref_date_str, signature]
    end
  end
end
