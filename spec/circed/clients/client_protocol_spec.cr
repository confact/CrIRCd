require "../../spec_helper"

private def protocol_client(*lines : String) : Tuple(Circed::Client, DummySocket)
  socket = DummySocket.new
  client = Circed::Client.new(socket.as(Circed::Network::SSLSocket::IRCSocket), lines.to_a)
  client.setup
  {client, socket}
end

private def password_test_config : Circed::Config
  Circed::Config.from_yaml(<<-YAML)
    host: "localhost"
    port: 6667
    max_users: 1000
    server_password: "secret"
    network: "TestNet"
    link_password: "link-secret"
    YAML
end

describe "IRC client protocol validation" do
  before_each { clear_repositories }
  after_each { clear_repositories }

  it "requires registration for query commands" do
    _, socket = protocol_client("LIST")

    socket.sent_data.join.should contain(" 451 * :You have not registered")
  end

  it "uses ERR_NONICKNAMEGIVEN for NICK without a nickname" do
    _, socket = protocol_client("NICK")

    socket.sent_data.join.should contain(" 431 * :No nickname given")
  end

  it "uses ERR_NOORIGIN for PING without an origin" do
    _, socket = protocol_client("PING")

    socket.sent_data.join.should contain(" 409 * :No origin specified")
  end

  it "distinguishes missing PRIVMSG recipients and text" do
    _, socket = protocol_client(
      "NICK Alice",
      "USER alice 0 * :Alice",
      "PRIVMSG",
      "PRIVMSG Bob"
    )

    responses = socket.sent_data.join
    responses.should contain(" 411 Alice :No recipient given (PRIVMSG)")
    responses.should contain(" 412 Alice :No text to send")
  end

  it "rejects USER after registration" do
    _, socket = protocol_client(
      "NICK Alice",
      "USER alice 0 * :Alice",
      "USER alice 0 * :Alice Again"
    )

    socket.sent_data.join.should contain(" 462 Alice :You may not reregister")
  end

  it "rejects PASS after registration" do
    _, socket = protocol_client(
      "NICK Alice",
      "USER alice 0 * :Alice",
      "PASS secret"
    )

    socket.sent_data.join.should contain(" 462 Alice :You may not reregister")
  end

  it "validates required WHOIS and MODE parameters" do
    _, socket = protocol_client(
      "NICK Alice",
      "USER alice 0 * :Alice",
      "WHOIS",
      "MODE"
    )

    responses = socket.sent_data.join
    responses.should contain(" 431 Alice :No nickname given")
    responses.should contain(" 461 Alice MODE :Not enough parameters")
  end

  it "reports online users with ISON using RFC1459 lookup" do
    Circed::Network::NetworkState.add_user("Bob[One]", "bob", "remote.host", "Bob", "remote")

    _, socket = protocol_client(
      "NICK Alice",
      "USER alice 0 * :Alice",
      "ISON aLICE bOB{oNE} Missing"
    )

    socket.sent_data.join.should contain(" 303 Alice :Alice Bob[One]")
  end

  it "formats USERHOST status and limits queries to five nicknames" do
    6.times do |index|
      nickname = "User#{index}"
      Circed::Network::NetworkState.add_user(nickname, "user#{index}", "host#{index}", nickname, "remote")
    end
    user = Circed::Network::NetworkState.get_user("User0")
    user.should_not be_nil
    user.try { |existing_user| existing_user.modes << 'o' }
    Circed::Network::NetworkState.set_user_away("User0", "Gone")

    _, socket = protocol_client(
      "NICK Alice",
      "USER alice 0 * :Alice",
      "USERHOST uSER0 User1 User2 User3 User4 User5"
    )

    reply = socket.sent_data.find(&.includes?(" 302 Alice "))
    reply.should_not be_nil
    reply.try do |line|
      line.should contain(":User0*=-user0@host0 User1=+user1@host1 User2=+user2@host2 User3=+user3@host3 User4=+user4@host4")
      line.should_not contain("User5")
    end
  end

  it "requires parameters for ISON and USERHOST" do
    _, socket = protocol_client(
      "NICK Alice",
      "USER alice 0 * :Alice",
      "ISON",
      "USERHOST"
    )

    responses = socket.sent_data.join
    responses.should contain(" 461 Alice ISON :Not enough parameters")
    responses.should contain(" 461 Alice USERHOST :Not enough parameters")
  end

  it "sends LUSERS and MOTD after registration and on request" do
    _, socket = protocol_client(
      "NICK Alice",
      "USER alice 0 * :Alice",
      "LUSERS",
      "MOTD"
    )

    lines = socket.sent_data.join.lines
    lines.count(&.includes?(" 251 Alice ")).should eq(2)
    lines.count(&.includes?(" 376 Alice ")).should eq(2)
    lines.any?(&.includes?(" 252 Alice 0 :IRC Operators online")).should be_true
    lines.any?(&.includes?(" 372 Alice :- Welcome to Circd Server")).should be_true
  end

  it "does not register without the configured server password" do
    original_config = Circed::Server.config
    Circed::Server.config = password_test_config

    client, socket = protocol_client("NICK Alice", "USER alice 0 * :Alice")

    client.registered?.should be_false
    socket.sent_data.join.should contain(" 464 Alice :Password incorrect")
  ensure
    Circed::Server.config = original_config if original_config
  end

  it "completes registration when a valid PASS arrives" do
    original_config = Circed::Server.config
    Circed::Server.config = password_test_config

    client, socket = protocol_client("NICK Alice", "USER alice 0 * :Alice", "PASS secret")

    client.registered?.should be_true
    socket.sent_data.join.should contain(" 001 Alice ")
    socket.sent_data.join.should_not contain(" 462 Alice ")
  ensure
    Circed::Server.config = original_config if original_config
  end
end
