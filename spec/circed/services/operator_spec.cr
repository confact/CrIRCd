require "../../spec_helper"

def operator_test_config : Circed::Config
  Circed::Config.from_yaml(<<-YAML)
    host: "localhost"
    port: 6667
    max_users: 1000
    server_password: nil
    network: "TestNet"
    link_password: "password"
    operators:
      - name: "global"
        password: "secret"
        hosts:
          - "*!test@localhost"
      - name: "local"
        password: "local-secret"
        local: true
        hosts:
          - "localhost"
      - name: "remote"
        password: "remote-secret"
        hosts:
          - "*.example.com"
    YAML
end

class RecordingLinkServer < Circed::LinkServer
  getter sent_messages = [] of String

  def initialize(@name : String, target_host : String? = nil, @target_port : Int32 = 6667)
    @target_host = target_host || @name
  end

  def safe_send(message : String) : Bool
    @sent_messages << message
    true
  end

  def close(reason : String = "Closing connection")
    @sent_messages << "CLOSE #{reason}"
  end

  def closed? : Bool
    false
  end
end

describe "IRC operator support" do
  original_config = Circed::Server.config

  before_each do
    clear_repositories
    Circed::Network::NetworkState.clear_all_state
    Circed::ServerHandler.servers.clear
    Circed::Server.config = operator_test_config
  end

  after_each do
    clear_repositories
    Circed::Network::NetworkState.clear_all_state
    Circed::ServerHandler.servers.clear
    Circed::Server.config = original_config
  end

  it "grants global operator privileges with OPER" do
    client = create_test_client("Alice")

    Circed::Infrastructure::ServiceLocator.irc_service.oper(client, "global", "secret")

    user = user_repository.get("Alice")
    user.should_not be_nil
    user.try(&.modes.includes?('o')).should be_true
    user.try(&.modes.includes?('O')).should be_false

    sent = client.socket.as(DummySocket).sent_data.join
    sent.should contain(" 381 Alice :You are now an IRC operator")
    sent.should contain(" MODE Alice +o")
  end

  it "grants local operator privileges with OPER" do
    client = create_test_client("Alice")

    Circed::Infrastructure::ServiceLocator.irc_service.oper(client, "local", "local-secret")

    user = user_repository.get("Alice")
    user.should_not be_nil
    user.try(&.modes.includes?('O')).should be_true
    user.try(&.modes.includes?('o')).should be_false

    client.socket.as(DummySocket).sent_data.join.should contain(" MODE Alice +O")
  end

  it "replaces stale operator modes in local and network state" do
    client = create_test_client("Alice")
    Circed::Network::NetworkState.add_user("Alice", "test", "localhost", "Alice", "test_server")

    service = Circed::Infrastructure::ServiceLocator.irc_service
    service.oper(client, "global", "secret")
    service.oper(client, "local", "local-secret")

    local_modes = user_repository.get("Alice").try(&.modes)
    local_modes.should_not be_nil
    local_modes.try(&.includes?('O')).should be_true
    local_modes.try(&.includes?('o')).should be_false

    network_modes = Circed::Network::NetworkState.get_user("Alice").try(&.modes)
    network_modes.should_not be_nil
    network_modes.try(&.includes?('O')).should be_true
    network_modes.try(&.includes?('o')).should be_false

    client.socket.as(DummySocket).sent_data.join.should contain(" MODE Alice -o+O")
  end

  it "rejects bad operator passwords" do
    client = create_test_client("Alice")

    Circed::Infrastructure::ServiceLocator.irc_service.oper(client, "global", "wrong")

    user_repository.get("Alice").try(&.modes.includes?('o')).should be_false
    client.socket.as(DummySocket).sent_data.join.should contain(" 464 Alice :Password incorrect")
  end

  it "rejects operator requests from disallowed hosts" do
    client = create_test_client("Alice")

    Circed::Infrastructure::ServiceLocator.irc_service.oper(client, "remote", "remote-secret")

    user_repository.get("Alice").try(&.modes.includes?('o')).should be_false
    client.socket.as(DummySocket).sent_data.join.should contain(" 491 Alice :No O-lines for your host")
  end

  it "ignores direct attempts to self-grant operator mode" do
    client = create_test_client("Alice")

    Circed::Actions::Mode.call(client, ["Alice", "+o"])

    user_repository.get("Alice").try(&.modes.includes?('o')).should be_false
  end

  it "allows IRC operators to kill local users" do
    oper = create_test_client("Alice")
    victim = create_test_client("Bob")
    user_repository.get("Alice").try { |user| user.modes << 'o' }

    Circed::Infrastructure::ServiceLocator.irc_service.kill_user(oper, "Bob", "Testing")

    user_repository.get("Bob").should be_nil
    victim.socket.as(DummySocket).sent_data.join.should contain("ERROR :Killed by Alice: Testing")
  end

  it "rejects local operator KILL for remote users" do
    oper = create_test_client("Alice")
    user_repository.get("Alice").try { |user| user.modes << 'O' }
    Circed::Network::NetworkState.add_user("RemoteBob", "bob", "remote.example", "Bob", "remote.server", 1)

    Circed::Infrastructure::ServiceLocator.irc_service.kill_user(oper, "RemoteBob", "Testing")

    Circed::Network::NetworkState.get_user("RemoteBob").should_not be_nil
    oper.socket.as(DummySocket).sent_data.join.should contain(" 481 Alice :Permission Denied- You're not a global IRC operator")
  end

  it "allows global operator KILL for remote users" do
    oper = create_test_client("Alice")
    user_repository.get("Alice").try { |user| user.modes << 'o' }
    Circed::Network::NetworkState.add_user("RemoteBob", "bob", "remote.example", "Bob", "remote.server", 1)

    Circed::Infrastructure::ServiceLocator.irc_service.kill_user(oper, "RemoteBob", "Testing")

    Circed::Network::NetworkState.get_user("RemoteBob").should be_nil
  end

  it "rejects KILL from non-operators" do
    client = create_test_client("Alice")
    create_test_client("Bob")

    Circed::Infrastructure::ServiceLocator.irc_service.kill_user(client, "Bob", "Testing")

    user_repository.get("Bob").should_not be_nil
    client.socket.as(DummySocket).sent_data.join.should contain(" 481 Alice :Permission Denied- You're not an IRC operator")
  end

  it "rejects KILL targeting servers" do
    oper = create_test_client("Alice")
    user_repository.get("Alice").try { |user| user.modes << 'o' }

    Circed::Infrastructure::ServiceLocator.irc_service.kill_user(oper, "irc.example.com", "Testing")

    oper.socket.as(DummySocket).sent_data.join.should contain(" 483 Alice irc.example.com :You can't kill a server!")
  end

  it "requires operator privileges for administrative commands" do
    client = create_test_client("Alice")
    service = Circed::Infrastructure::ServiceLocator.irc_service

    service.rehash(client)
    service.connect_server(client, "irc.example.com")
    service.squit_server(client, "irc.example.com", "Testing")
    service.die(client, "Testing")
    service.restart(client, "Testing")

    sent = client.socket.as(DummySocket).sent_data.join
    sent.scan(/ 481 Alice /).size.should eq(5)
  end

  it "keeps DIE and RESTART disabled unless explicitly configured" do
    oper = create_test_client("Alice")
    user_repository.get("Alice").try { |user| user.modes << 'o' }
    service = Circed::Infrastructure::ServiceLocator.irc_service

    service.die(oper, "Testing")
    service.restart(oper, "Testing")

    sent = oper.socket.as(DummySocket).sent_data.join
    sent.should contain(" 481 Alice :DIE is disabled in server configuration")
    sent.should contain(" 481 Alice :RESTART is disabled in server configuration")
  end

  it "returns server errors for CONNECT and SQUIT targets it cannot resolve" do
    oper = create_test_client("Alice")
    user_repository.get("Alice").try { |user| user.modes << 'o' }
    service = Circed::Infrastructure::ServiceLocator.irc_service

    service.connect_server(oper, "irc.example.com")
    service.squit_server(oper, "irc.example.com", "Testing")

    sent = oper.socket.as(DummySocket).sent_data.join
    sent.should contain(" 263 Alice CONNECT :Please wait a while and try again.")
    sent.should contain(" 402 Alice irc.example.com :No such server")
  end

  it "rejects local operator CONNECT forwarding to another server" do
    oper = create_test_client("Alice")
    user_repository.get("Alice").try { |user| user.modes << 'O' }

    Circed::Infrastructure::ServiceLocator.irc_service.connect_server(oper, "irc.example.com", nil, "remote.server.com")

    oper.socket.as(DummySocket).sent_data.join.should contain(" 481 Alice :Permission Denied- You're not a global IRC operator")
  end

  it "routes remote CONNECT through the next network hop" do
    oper = create_test_client("Alice")
    user_repository.get("Alice").try { |user| user.modes << 'o' }
    next_hop = RecordingLinkServer.new("hub.server")
    Circed::ServerHandler.add_server(next_hop)
    Circed::Network::NetworkState.add_server("hub.server", 1, "Hub server")
    Circed::Network::NetworkState.add_server("remote.server", 2, "Remote server")
    Circed::Network::NetworkState.add_server_link(Circed::Server.name, "hub.server")
    Circed::Network::NetworkState.add_server_link("hub.server", "remote.server")

    Circed::Infrastructure::ServiceLocator.irc_service.connect_server(oper, "leaf.example.com", 7000, "remote.server")

    next_hop.sent_messages.should contain("CONNECT leaf.example.com 7000 remote.server")
  end

  it "routes remote SQUIT through the next network hop without closing it" do
    oper = create_test_client("Alice")
    user_repository.get("Alice").try { |user| user.modes << 'o' }
    next_hop = RecordingLinkServer.new("hub.server")
    Circed::ServerHandler.add_server(next_hop)
    Circed::Network::NetworkState.add_server("hub.server", 1, "Hub server")
    Circed::Network::NetworkState.add_server("remote.server", 2, "Remote server")
    Circed::Network::NetworkState.add_server_link(Circed::Server.name, "hub.server")
    Circed::Network::NetworkState.add_server_link("hub.server", "remote.server")

    Circed::Infrastructure::ServiceLocator.irc_service.squit_server(oper, "remote.server", "Testing")

    next_hop.sent_messages.should contain("SQUIT remote.server :Testing")
    next_hop.sent_messages.any?(&.starts_with?("CLOSE")).should be_false
  end
end
