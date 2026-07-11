require "../../spec_helper"

describe Circed::Actions::Who do
  before_each { clear_repositories }
  after_each { clear_repositories }

  it "marks IRC operators in WHO flags" do
    sender = create_test_client("Alice")
    create_test_client("Bob")
    user_repository["Bob"]?.try { |user| user.modes << 'o' }
    channel = create_test_channel("#test")
    channel.add_member("Alice")
    channel.add_member("Bob")
    channel.members["Bob"] << 'o'

    Circed::Actions::Who.call(sender, "#test")

    sender.socket.as(DummySocket).sent_data.join.should contain(" Bob H*@ :0 Bob")
  end

  it "does not mark the requester as an operator without operator mode" do
    sender = create_test_client("Alice")

    Circed::Actions::Who.call(sender, "Alice")

    sender.socket.as(DummySocket).sent_data.join.should contain(" Alice H :0 Alice")
  end

  it "lists visible users for an empty mask and supports wildcard fields" do
    sender = create_test_client("Alice")
    create_test_client("Bob")
    hidden = create_test_client("Hidden")
    user_repository[hidden.nickname.to_s]?.try { |user| user.modes << 'i' }
    Circed::Network::NetworkState.add_user("Remote", "remote", "users.example", "Remote User", "remote.server", 1)

    Circed::Actions::Who.call(sender)
    response = sender.socket.as(DummySocket).sent_data.join
    response.should contain(" Bob H :0 Bob")
    response.should_not contain(" Hidden ")
    response.should contain(" 315 Alice 0 :End of /WHO list")

    sender.socket.as(DummySocket).sent_data.clear
    Circed::Actions::Who.call(sender, "*.example")
    sender.socket.as(DummySocket).sent_data.join.should contain(" Remote H :1 Remote User")
  end

  it "shows invisible channel members only when the requester shares the channel" do
    sender = create_test_client("Alice")
    create_test_client("Hidden")
    user_repository["Hidden"]?.try { |user| user.modes << 'i' }
    channel_repository.add_member("#test", "Hidden")

    Circed::Actions::Who.call(sender, "#test")
    sender.socket.as(DummySocket).sent_data.join.should_not contain(" Hidden ")

    channel_repository.add_member("#test", "Alice")
    sender.socket.as(DummySocket).sent_data.clear
    Circed::Actions::Who.call(sender, "#test")
    sender.socket.as(DummySocket).sent_data.join.should contain(" Hidden H :0 Hidden")
  end

  it "supports operator-only WHO and reports away status" do
    sender = create_test_client("Alice")
    create_test_client("Oper")
    create_test_client("Regular")
    user_repository["Oper"]?.try { |user| user.modes << 'o' }
    Circed::Network::NetworkState.get_user("Oper").try { |user| user.modes << 'o' }
    Circed::Network::NetworkState.set_user_away("Oper", "Gone")

    Circed::Actions::Who.call(sender, "0", true)

    response = sender.socket.as(DummySocket).sent_data.join
    response.should contain(" Oper G* :0 Oper")
    response.should_not contain(" Regular ")
  end
end
