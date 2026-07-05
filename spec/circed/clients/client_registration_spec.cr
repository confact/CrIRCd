require "../../spec_helper"

def with_real_outbound_writer(&)
  previous = ENV["CIRCED_TEST"]?
  ENV.delete("CIRCED_TEST")
  yield
ensure
  if value = previous
    ENV["CIRCED_TEST"] = value
  else
    ENV.delete("CIRCED_TEST")
  end
end

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
    client.hostmask.should eq("Alice!alice@localhost")
  end

  it "applies RFC USER mode bits during registration" do
    socket = DummySocket.new
    client = Circed::Client.new(socket.as(Circed::Network::SSLSocket::IRCSocket), [] of String)

    Circed::Actions::Nick.call(client, "Alice")
    client.user = ["alice", "12", "*", ":Alice Example"]

    user = user_repository.get("Alice")
    user.should_not be_nil
    user.try(&.modes.includes?('w')).should be_true
    user.try(&.modes.includes?('i')).should be_true
  end

  it "batches queued client messages into a single socket write" do
    with_real_outbound_writer do
      socket = DummySocket.new
      client = Circed::Client.new(socket.as(Circed::Network::SSLSocket::IRCSocket), [] of String)

      client.send_message("PING :one")
      client.send_message("PING :two")
      client.send_message("PING :three")

      20.times do
        break unless socket.sent_data.empty?
        sleep 10.milliseconds
      end

      socket.sent_data.size.should eq(1)
      socket.sent_data.first.should contain("PING :one\r\nPING :two\r\nPING :three\r\n")

      client.shutdown
    end
  end

  it "terminates direct client messages with CRLF" do
    client = create_test_client("Alice")
    socket = client.socket.as(DummySocket)

    client.send_message("PING :one")

    socket.sent_data.last.should eq("PING :one\r\n")
  end
end
