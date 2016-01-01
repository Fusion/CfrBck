require "openssl"

module LocalCrypto
  class MD5Delegate
    include OpenSSL

    def initialize
      @digest = Digest.new "md5"
    end

    def update(data : String | Slice)
      @digest.update data
    end

    def finish
      # noop!
    end

    def to_s
      @digest.to_s
    end
  end
end
