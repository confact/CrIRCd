require "../../spec_helper"

describe Circed::Client do
  before_each do
    clear_repositories
  end

  after_each do
    clear_repositories
  end

  it "refreshes hostmask after nickname and user registration" do
    client = create_test_client("Alice")

    client.hostmask.should eq("Alice!test@localhost")
    client.registered?.should be_true
  end

  it "completes registration when USER arrives before NICK" do
    socket = DummySocket.new
    client = Circed::Client.new(socket.as(Circed::Network::SSLSocket::IRCSocket), [] of String)

    client.user = ["alice", "0", "*", ":Alice Example"]
    client.registered?.should be_false

    Circed::Actions::Nick.call(client, "Alice")

    client.registered?.should be_true
    client.hostmask.should eq("Alice!alice@ssl_client")
  end
end
