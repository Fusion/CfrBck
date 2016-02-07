require "inifile"
require "http"
require "XML"
require "openssl/hmac"

module S3Util extend self

  class Actor
    S3Host = "s3.amazonaws.com"

    def initialize(auth_file_name)
      ini = IniFile.load(File.read FileUtil.canonical_path auth_file_name)
      @aws_keyid = ini["s3"]["id"]
      @aws_bucket = ini["s3"]["bucket"]
      @aws_access_control = "public-read"
      @aws_mime_type = "text/plain"
      @aws_key = ini["s3"]["secret"]
    end

    def work_dir(s, d)
      s + ".tmp"
    end

    def copy(source_path, dest_path, compress?)
      case compress?
      when FileUtil::Action::COMPRESS
        compress_copy(source_path, dest_path)
      when FileUtil::Action::EXPAND
        expand_copy(source_path, dest_path)
      else
        preserve_copy(source_path, dest_path)
      end
    end

    private def compress_copy(source_path, dest_path)
      #1 - compress to temp file
      #2 - upload temp file
      #3 - delete temp file
      if 0 != Compress.compress(source_path, dest_path.path)
        raise FileUtil::FileCompressionException.new "Error compressing #{source_path}"
      end
    end

    private def expand_copy(source_path, dest_path)
    end

    def preserve_copy(source_path, dest_path)
      resource_name = dest_path.basename
      File.open(source_path, "r")  do |file_in|
        response = put_(@aws_bucket, resource_name, file_in.size) do |server|
          bufsize = 4096
          buffer = Slice(UInt8).new(bufsize)
          complete = false
          until complete
            count = file_in.read(buffer)
            if count == bufsize
              server.write buffer
            else
              partial_buffer = Slice(UInt8).new(count) { |i| buffer[i] }
              server.write partial_buffer
              complete = true
            end
          end
        end
      end
    end

    private def extract_message(str)
      match = str.body.match(/<Message>(.+)<\/Message>/)
      match ? match[1] : str
    end

    private def get_(bucket, resource)
      verb = "GET"
      headers = HTTP::Headers.new
      headers["Host"] = S3.get_host(bucket)
      date, signature = S3.get_date_and_signature(verb, headers, "", @aws_key)
      headers["Date"] = date
      headers["Authorization"] = "AWS #{@aws_keyid}:#{signature}"

      http_client = HTTP::Client.new(S3Host, ssl: false)
      response = http_client.get("/#{resource}", headers: headers)
      p response
    end

    private def post_(host, point, headers)
      http_client = HTTP::Client.new(host, ssl: false)
      http_client.post(point, headers: headers)
    end

    private def put_(bucket, resource, size)
      verb = "PUT"
      headers = HTTP::Headers.new
      headers["Host"] = S3.get_host(bucket)
      headers["Content-Type"] ="text/plain"
      headers["Content-Length"] = size.to_s
      date, signature = S3.get_date_and_signature(verb, headers, resource, @aws_key)
      headers["Date"] = date
      headers["Authorization"] = "AWS #{@aws_keyid}:#{signature}"

      server = TCPSocket.new(S3Host, 80)
      server << "#{verb} /#{resource} HTTP/1.1\r\n"
      server << "Host: #{headers["Host"]}\r\n"
      #server << "Accept: #{headers["Accept"]}\r\n"
      server << "Content-Type: #{headers["Content-Type"]}\r\n"
      #server << "x-amz-acl: public-read\r\n" # necessary
      server << "Date: #{headers["Date"]}\r\n"
      server << "Content-Length: #{headers["Content-Length"]}\r\n"
      server << "Authorization: #{headers["Authorization"]}\r\n\r\n"

      yield server

      len = -1
      ctr = 0
      loop do
        r = server.gets.to_s
        p "R: #{r}"
        case len
        when .<= 0
          break if r == "\r\n"
          match = r.match(/Content-Length: ([0-9]+).*/)
          len = match.not_nil![1].to_i if match != nil
        else
          ctr += r.bytesize
          break if ctr >= len
        end
      end
      server.close
    end

    def normalized_path(canon, path)
      FileUtil.normalized_path(canon, path)
    end

    def prepare(location_in, location_out)
      FileUtil.prepare(location_in + ".tmp")
    end

    def retrieve_catalog(location, new_catalog_id)
      get_(@aws_bucket, "?prefix=catalog")
      FileUtil::RetrieveCatalogResult.new "", new_catalog_id
    end

    def write_catalog(location, new_catalog_id, caller)
      size = FileUtil.write_catalog(location, new_catalog_id, caller)
      File.open(FileUtil.catalog_path(location, new_catalog_id), "r")  do |file_in|
        response = put_(@aws_bucket, FileUtil.catalog_name(new_catalog_id), size) do |server|
          bufsize = 4096
          buffer = Slice(UInt8).new(bufsize)
          complete = false
          until complete
            count = file_in.read(buffer)
            if count == bufsize
              server.write buffer
            else
              partial_buffer = Slice(UInt8).new(count) { |i| buffer[i] }
              server.write partial_buffer
              complete = true
            end
          end
        end
      end
    end

    def test
      get_(@aws_bucket, "?prefix=catalog")
    end
  end
end
