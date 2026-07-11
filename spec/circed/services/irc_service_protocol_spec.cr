require "../../spec_helper"

describe "RFC channel and disconnect behavior" do
  before_each { clear_repositories }
  after_each { clear_repositories }

  it "uses the nickname as the default QUIT message" do
    alice = create_test_client("Alice")
    bob = create_test_client("Bob")
    channel_repository.add_member("#test", "Alice")
    channel_repository.add_member("#test", "Bob")

    Circed::Infrastructure::ServiceLocator.irc_service.quit_user(alice)

    bob.socket.as(DummySocket).sent_data.join.should contain("QUIT :Alice")
  end

  it "uses the nickname as the default PART message" do
    alice = create_test_client("Alice")
    bob = create_test_client("Bob")
    channel_repository.add_member("#test", "Alice")
    channel_repository.add_member("#test", "Bob")

    Circed::Infrastructure::ServiceLocator.irc_service.part_channel(alice, "#test")

    bob.socket.as(DummySocket).sent_data.join.should contain("PART #test :Alice")
  end

  it "allows external messages unless the channel is no-external" do
    alice = create_test_client("Alice")
    bob = create_test_client("Bob")
    channel = create_test_channel("#test")
    channel_repository.add_member("#test", "Bob")
    service = Circed::Infrastructure::ServiceLocator.irc_service

    service.route_message(alice, "#test", "open").should be_true

    channel.modes << 'n'
    service.route_message(alice, "#test", "blocked").should be_false
    bob.socket.as(DummySocket).sent_data.join.should contain("PRIVMSG #test :open")
    bob.socket.as(DummySocket).sent_data.join.should_not contain("PRIVMSG #test :blocked")
    alice.socket.as(DummySocket).sent_data.join.should contain(" 404 Alice #test :Cannot send to channel")
  end

  it "requires voice or operator status in moderated channels" do
    alice = create_test_client("Alice")
    bob = create_test_client("Bob")
    channel = create_test_channel("#test")
    channel_repository.add_member("#test", "Alice")
    channel_repository.add_member("#test", "Bob")
    channel.modes << 'm'
    service = Circed::Infrastructure::ServiceLocator.irc_service

    service.route_message(alice, "#test", "blocked").should be_false
    channel.members["Alice"] << 'v'
    service.route_message(alice, "#test", "voiced").should be_true

    bob.socket.as(DummySocket).sent_data.join.should contain("PRIVMSG #test :voiced")
  end

  it "prevents banned users from sending to a channel" do
    alice = create_test_client("Alice")
    bob = create_test_client("Bob")
    channel = create_test_channel("#test")
    channel_repository.add_member("#test", "Alice")
    channel_repository.add_member("#test", "Bob")
    channel.add_ban("Alice!*@*")

    Circed::Infrastructure::ServiceLocator.irc_service.route_message(alice, "#test", "blocked").should be_false

    bob.socket.as(DummySocket).sent_data.join.should_not contain("PRIVMSG #test :blocked")
  end

  it "allows voiced banned members to send" do
    alice = create_test_client("Alice")
    bob = create_test_client("Bob")
    channel = create_test_channel("#test")
    channel_repository.add_member("#test", "Alice")
    channel_repository.add_member("#test", "Bob")
    channel.add_ban("Alice!*@*")
    channel.members["Alice"] << 'v'

    Circed::Infrastructure::ServiceLocator.irc_service.route_message(alice, "#test", "allowed").should be_true

    bob.socket.as(DummySocket).sent_data.join.should contain("PRIVMSG #test :allowed")
  end

  it "hides channel keys and limits from non-members" do
    alice = create_test_client("Alice")
    channel = create_test_channel("#test")
    channel.password = "secret"
    channel.user_limit = 10

    Circed::Infrastructure::ServiceLocator.irc_service.query_mode(alice, "#test")

    response = alice.socket.as(DummySocket).sent_data.find!(&.includes?(" 324 "))
    response.should contain("+kl")
    response.should_not contain("secret")
    response.should_not contain(" 10")
  end

  it "treats secret channels as nonexistent for TOPIC queries by non-members" do
    alice = create_test_client("Alice")
    channel = create_test_channel("#secret")
    channel.modes << 's'
    channel.topic = "Hidden"

    Circed::Infrastructure::ServiceLocator.irc_service.query_topic(alice, "#secret").should be_false

    alice.socket.as(DummySocket).sent_data.join.should contain(" 403 Alice #secret :No such channel")
  end
end
