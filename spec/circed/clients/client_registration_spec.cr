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
    Circed::Network::LineState.clear
  end

  after_each do
    clear_repositories
    Circed::Network::LineState.clear
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

    user = user_repository["Alice"]?
    user.should_not be_nil
    user.try(&.modes.includes?('w')).should be_true
    user.try(&.modes.includes?('i')).should be_true
  end

  it "rejects registration when a K-line matches the user hostmask" do
    Circed::Network::LineState.add("KLINE", "*@localhost", "Banned host", "oper")
    socket = DummySocket.new
    client = Circed::Client.new(socket.as(Circed::Network::SSLSocket::IRCSocket), [] of String)

    Circed::Actions::Nick.call(client, "Alice")
    client.user = ["alice", "0", "*", ":Alice Example"]

    client.registered?.should be_false
    user_repository["Alice"]?.should be_nil
    socket.sent_data.join.should contain(" 465 Alice :You are banned from this server (Banned host)")
  end

  it "rejects registration when a Z-line matches the remote IP" do
    Circed::Network::LineState.add("ZLINE", "127.0.0.0/8", "Open proxy", "oper")
    socket = DummySocket.new
    client = Circed::Client.new(socket.as(Circed::Network::SSLSocket::IRCSocket), [] of String)

    Circed::Actions::Nick.call(client, "Alice")
    client.user = ["alice", "0", "*", ":Alice Example"]

    client.registered?.should be_false
    socket.sent_data.join.should contain(" 465 Alice :You are banned from this server (Open proxy)")
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

    client.send_message("PING :two\r\n")

    socket.sent_data.last.should eq("PING :two\r\n")
  end

  it "rate limits expensive command bursts" do
    socket = DummySocket.new
    client = Circed::Client.new(socket.as(Circed::Network::SSLSocket::IRCSocket), ["LIST", "LIST", "LIST"])

    client.setup

    socket.sent_data.join.should contain(" 263 * LIST :Please wait a while and try again.")
  end

  it "rejects oversized IRC messages" do
    socket = DummySocket.new
    line = "PRIVMSG #test :#{"x" * Circed::Client::MAX_MESSAGE_BYTES}"
    client = Circed::Client.new(socket.as(Circed::Network::SSLSocket::IRCSocket), [line])

    client.setup

    socket.sent_data.join.should contain(" 417 * :Input line was too long")
  end

  it "notifies shared channel members before removing a quitting user" do
    alice = create_test_client("Alice")
    bob = create_test_client("Bob")
    channel_repository.add_member("#test", "Alice")
    channel_repository.add_member("#test", "Bob")

    Circed::Infrastructure::ServiceLocator.irc_service.quit_user(alice, "Leaving")

    bob.socket.as(DummySocket).sent_data.join.should contain(":Alice!test@localhost QUIT :Leaving")
  end
end
