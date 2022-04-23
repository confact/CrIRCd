require "../../spec_helper"

describe Circed::User do
  # TODO: Write tests
  it "should be OK" do
    Circed::User.new(nil, "0", "test", "testname").should be_a(Circed::User)
  end

  it "should return stirng" do
    Circed::User.new(nil, "0", "test", "testname").to_s.should eq("test 0 :testname")
  end

  it "should access variables" do
    user = Circed::User.new(nil, "0", "test", "testname")
    user.mode.should eq("0")
    user.name.should eq("test")
    user.realname.should eq("testname")
  end
end
