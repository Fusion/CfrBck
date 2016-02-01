require "./spec_helper"

TP = "spectest"
RF = File.join(TP, "regular_file")
SL = File.join(TP, "symbolic_link")

def bringup
  Dir.mkdir(TP) if !File.exists?(TP)
  begin File.delete(SL); rescue; end
  if !File.exists?(RF)
    File.open(RF, "w") do |f|
      f.print "regular content"
    end
  end
end

def expect_raises_not
  ex = nil
  begin
    yield
  rescue ex
    backtrace = ex.backtrace.map { |f| "  # #{f}" }.join "\n"
    fail "no exception expected, got <#{ex.class}: #{ex.to_s}> with backtrace:\n#{backtrace}"
  end
end

bringup

describe Cfrbck do
  describe "file operations" do
    it "should create a symlink" do
      expect_raises_not do
        FileUtil.symlink(RF, SL, false)
        File.lstat(SL)
      end
    end
    it "should create a symlink, but only once" do
      expect_raises(FileUtil::FileUtilException) do
        FileUtil.symlink(RF, SL, false)
      end
    end
    it "should create a symlink again when forced" do
      expect_raises_not { FileUtil.symlink(RF, SL, true) }
    end
    it "should read a link target" do
      real_name = ""
      expect_raises_not do
        real_name = FileUtil.readlink(SL)
      end
      real_name.should eq("spectest/regular_file")
    end
    it "should change file permissions" do
      expect_raises_not { FileUtil.chmod(RF, 0o600) }
      File.stat(RF).perm.should eq(0o600)
    end
  end
end
