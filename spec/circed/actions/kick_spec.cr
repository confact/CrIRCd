require "../../spec_helper"


def create_test_client(nickname : String) : Circed::Client
  client = Circed::Client.new(DummySocket.new)
  client.nickname = nickname
  client.set_user(["test", "test", "test", nickname])
  Circed::UserHandler.add_client(client)
  client
end

describe Circed::Actions::Kick do
  before_each do
    # Initialize and set up your mocks
    Circed::UserHandler.clear
    Circed::ChannelHandler.clear
  end

  after_each do
    # Clean up your mocks
    Circed::UserHandler.clear
    Circed::ChannelHandler.clear
  end

  it "kicks a user from a channel" do
    sender = create_test_client("Alice")
    kicked_user = create_test_client("Bob")
    channel = Circed::Channel.new("#test")
    channel.add_client(sender)
    channel.add_client(kicked_user)

    Circed::ChannelHandler.add_channel(channel)

    Circed::Actions::Kick.kick(sender, channel, "Bob", "testing kick")

    channel.user_in_channel?(kicked_user).should be_false
  end

  it "does not kick a user if sender is not an operator" do
    sender = create_test_client("Alice")
    kicked_user = create_test_client("Bob")
    channel = Circed::Channel.new("#test")
    channel.add_client(sender)
    channel.add_client(kicked_user)
    channel.find_user(sender).not_nil!.remove_mode("o")

    channel.user_in_channel?(sender).should be_true

    channel.find_user(sender).not_nil!.user_mode.to_s.should eq("")

    Circed::ChannelHandler.add_channel(channel)

    Circed::Actions::Kick.kick(sender, channel, "Bob", "testing kick")

    channel.user_in_channel?(kicked_user).should be_true
  end
end