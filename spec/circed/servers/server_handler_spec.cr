require "../../spec_helper"

describe Circed::ServerHandler do
  it "stores linked servers in a set" do
    Circed::ServerHandler.servers.should be_a(Set(Circed::LinkServer))
  end
end
