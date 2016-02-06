@[Link("minizs3")]
lib LibMS
  fun aws_set_key(key: UInt8*)
  fun aws_set_keyid(key: UInt8*)
  fun aws_set_accesscontrol(accesscontrol: UInt8*)
  fun aws_set_mimetype(mimetype: UInt8*)
  fun getStringToSign(date: UInt8**, method: UInt8*, bucket: UInt8*, file: UInt8*, acl?: Int8): UInt8*
  fun cr_aws_put(date: UInt8*, signature: UInt8*, resource_name: UInt8*, resource_path: UInt8*, bucket: UInt8*)
  fun cr_aws_put_compress(date: UInt8*, signature: UInt8*, resource_name: UInt8*, resource_path: UInt8*, bucket: UInt8*)
end

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
      LibMS.aws_set_key(ini["s3"]["secret"].to_unsafe)
      LibMS.aws_set_keyid(@aws_keyid.to_unsafe)
      LibMS.aws_set_accesscontrol(@aws_access_control)
      LibMS.aws_set_mimetype(@aws_mime_type)
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
      host = "#{@aws_bucket}.s3.amazonaws.com"
      date, signature = date_and_signature("#{resource_name}", "PUT", true)
      File.open(source_path, "r")  do |file_in|
        response = put_(host, "/#{resource_name}",
            get_headers(HeaderType::CONTENT, host, date, file_in.size, signature)) do |server|
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

    # When using multipart, each part must be 5MB in size, save for last one.
    # Otherwise use simple put!
    private def c_put_multipart(resource_name, resource_path)
      #LibMS.cr_aws_put(date, signature, resource_name, resource_path, @aws_bucket)
      #LibMS.cr_aws_put_compress(date, signature, resource_name, resource_path, @aws_bucket)
      success = false
      host = "#{@aws_bucket}.s3.amazonaws.com"
      etags = [] of String # parts

      date, signature = date_and_signature("#{resource_name}?uploads", "POST", true)
      response = post_(host, "/#{resource_name}?uploads",
          get_headers(HeaderType::HELLO, host, date, 0, signature))

      if response.status_code == 200
        upload_id = XML.parse(response.body).children[0].children.find { |node| node.name == "UploadId" }.not_nil!.children[0]
        part_number = 1

        date, signature = date_and_signature("#{resource_name}?partNumber=#{part_number}&uploadId=#{upload_id}", "PUT", false)
        response = put_(host, "/#{resource_name}?partNumber=#{part_number}&uploadId=#{upload_id}",
            get_headers(HeaderType::CONTENT, host, date, 5, signature))

        if response.status_code == 200
          etags << response.headers["ETag"]
          part_number += 1

          date, signature = date_and_signature("#{resource_name}?partNumber=#{part_number}&uploadId=#{upload_id}", "PUT", false)
          response = put_(host, "/#{resource_name}?partNumber=#{part_number}&uploadId=#{upload_id}",
              get_headers(HeaderType::CONTENT, host, date, 5, signature))

          if response.status_code == 200
            etags << response.headers["ETag"]
            pn = 1
            body = String.build do |body|
              body << "<CompleteMultipartUpload>\n"
              etags.each do |etag|
                body << "  <Part>\n    <PartNumber>#{pn}</PartNumber>\n    <ETag>#{etag}</ETag>\n  </Part>\n"
                pn += 1
              end
              body << "</CompleteMultipartUpload>\n"
            end

            date, signature = date_and_signature("#{resource_name}?uploadId=#{upload_id}", "POST", false)
            # TODO This guy gets an error code
            response = post_(host, "/#{resource_name}?uploadId=#{upload_id}",
                get_headers(HeaderType::BYE, host, date, 0, signature))

            if response.status_code == 200
              success = true
            end
          end
        end

        if !success
        raise <<-EOB
          Unable to upload multipart file (#{response.status_code}):
          #{extract_message(response)}
          EOB
        end
      end
    end

    private def date_and_signature(resource, method, acl?)
      #ref_date_ptr = Pointer(UInt8*).malloc(1)
      #signature = String.new(LibMS.getStringToSign(ref_date_ptr, method, @aws_bucket, resource, acl? ? 1 : 0))
      #ref_date_str = String.new ref_date_ptr.value
      a_date = HTTP.rfc1123_date(Time.now)
      a_resource = "#{@aws_bucket}/#{resource}"
      if @aws_access_control  && acl?
        a_acl = "x-amz-acl:#{@aws_access_control}\n"
      else
        a_acl = ""
      end
      if @aws_mime_type
        a_mime_type = @aws_mime_type
      else
        a_mime_type = ""
      end
      tosign = "#{method}\n\n#{a_mime_type}\n#{a_date}\n#{a_acl}/#{a_resource}"
      rawsig = OpenSSL::HMAC.digest(:sha1, @aws_key, tosign)
      signature = Base64.encode(rawsig).chomp
      [a_date, signature]
    end

    private def extract_message(str)
      match = str.body.match(/<Message>(.+)<\/Message>/)
      match ? match[1] : str
    end

    private def get_(host, point, headers)
      http_client = HTTP::Client.new(host, ssl: false)
      http_client.get(point, headers: headers)
    end

    private def post_(host, point, headers)
      http_client = HTTP::Client.new(host, ssl: false)
      http_client.post(point, headers: headers)
    end

    private def put_(host, point, headers)
      server = TCPSocket.new(S3Host, 80)
      server << "PUT #{point} HTTP/1.1\r\n"
      server << "Host: #{headers["Host"]}\r\n"
      server << "Accept: #{headers["Accept"]}\r\n"
      server << "Content-Type: #{headers["Content-Type"]}\r\n"
      server << "x-amz-acl: public-read\r\n" # necessary
      server << "Date: #{headers["Date"]}\r\n"
      server << "Content-Length: #{headers["Content-Length"]}\r\n"
      server << "Authorization: #{headers["Authorization"]}\r\n\r\n"

      yield server

      len = -1
      ctr = 0
      loop do
        r = server.gets.to_s
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

    enum HeaderType
      HELLO
      CONTENT
      BYE
    end

    private def get_headers(type, host, date, length, signature)
      headers = HTTP::Headers.new
      case type
      when HeaderType::HELLO
        headers["Host"] = host
        headers["Accept"] = "*/*"
        headers["Content-Type"] = "text/plain"
        headers["x-amz-acl"] = "public-read"
        headers["Date"] = date
        headers["Authorization"] = "AWS #{@aws_keyid}:#{signature}"
      when HeaderType::CONTENT
        headers["Host"] = host
        headers["Accept"] = "*/*"
        headers["Content-Type"] = "text/plain"
        headers["Date"] = date
        headers["Content-Length"] = length.to_s
        headers["Authorization"] = "AWS #{@aws_keyid}:#{signature}"
      when HeaderType::BYE
        headers["Host"] = host
        headers["Accept"] = "*/*"
        headers["Content-Type"] = "text/plain"
        headers["Date"] = date
        headers["Authorization"] = "AWS #{@aws_keyid}:#{signature}"
      end
      headers
    end

    def normalized_path(canon, path)
      FileUtil.normalized_path(canon, path)
    end

    def retrieve_catalog(location, new_catalog_id)
      host = "#{@aws_bucket}.s3.amazonaws.com"
      #date, signature = date_and_signature("#{resource_name}", "GET", true)
      FileUtil.retrieve_catalog(location, new_catalog_id)
    end

    def test
      verb = "put"
      # -
      headers = HTTP::Headers.new
      headers["Host"] = S3.get_host(@aws_bucket)
      headers["Content-Type"] ="image/jpeg"
      resource = "photos/puppy.jpg"
      date, signature = S3.get_date_and_signature(verb, headers, resource)
      headers["Date"] = date
      headers["Authorization"] = "AWS: #{signature}"

      p headers
    end
  end
end
