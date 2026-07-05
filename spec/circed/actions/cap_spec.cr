require "../../spec_helper"

describe Circed::Actions::Cap do
  before_each do
    clear_repositories
  end

  after_each do
    clear_repositories
  end

  it "does not advertise unsupported IRCv3 capabilities" do
    sender = create_test_client("Alice")

    Circed::Actions::Cap.call(sender, "LS")

    data = sender.socket.as(DummySocket).sent_data.join
    data.should contain(" CAP * LS :")
    data.should_not contain("multi-prefix")
    data.should_not contain("extended-join")
    data.should_not contain("sasl")
  end

  it "allows CAP negotiation before nickname registration" do
    socket = DummySocket.new
    sender = Circed::Client.new(socket.as(Circed::Network::SSLSocket::IRCSocket), [] of String)

    Circed::Actions::Cap.call(sender, "LS")

    socket.sent_data.join.should contain(" CAP * LS :")
  end

  it "NAKs requested capabilities that are not implemented" do
    sender = create_test_client("Alice")

    Circed::Actions::Cap.call(sender, "REQ", "multi-prefix server-time")

    data = sender.socket.as(DummySocket).sent_data.join
    data.should contain(" CAP * NAK :multi-prefix server-time")
  end
end
