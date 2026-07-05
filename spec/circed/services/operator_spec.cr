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

describe "IRC operator support" do
  original_config = Circed::Server.config

  before_each do
    clear_repositories
    Circed::Server.config = operator_test_config
  end

  after_each do
    clear_repositories
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
    service.wallops(client, "Testing")

    sent = client.socket.as(DummySocket).sent_data.join
    sent.scan(/ 481 Alice /).size.should eq(6)
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

  it "sends WALLOPS from operators to local wallops users" do
    oper = create_test_client("Alice")
    wallops_user = create_test_client("Bob")
    quiet_user = create_test_client("Carol")
    user_repository.get("Alice").try { |user| user.modes << 'o' }
    user_repository.get("Bob").try { |user| user.modes << 'w' }

    Circed::Infrastructure::ServiceLocator.irc_service.wallops(oper, "Server notice")

    wallops_user.socket.as(DummySocket).sent_data.join.should contain(":localhost WALLOPS :Server notice")
    quiet_user.socket.as(DummySocket).sent_data.join.should_not contain("WALLOPS")
  end
end
