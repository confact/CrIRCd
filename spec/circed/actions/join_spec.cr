require "../../spec_helper"

def create_test_client(nickname : String) : Circed::Client
  client = Circed::Client.new(DummySocket.new)
  client.nickname = nickname
  client.set_user(["test", "test", "test", nickname])
  Circed::UserHandler.add_client(client)
  client
end

describe Circed::Actions::Join do
  before_each do
    Circed::UserHandler.clear
    Circed::ChannelHandler.clear
  end

  after_each do
    Circed::UserHandler.clear
    Circed::ChannelHandler.clear
  end

  it "joins a user to a channel" do
    sender = create_test_client("Alice")
    channel_name = "#test"
    channel = Circed::Channel.new(channel_name)
    Circed::ChannelHandler.add_channel(channel)

    Circed::Actions::Join.call(sender, channel_name)

    channel.user_in_channel?(sender).should be_true
  end

  it "does not join a user to a private channel" do
    sender = create_test_client("Alice")
    channel_name = "#private"
    channel = Circed::Channel.new(channel_name)
    channel.add_mode("i") # Make the channel invite-only
    Circed::ChannelHandler.add_channel(channel)

    Circed::Actions::Join.call(sender, channel_name)

    channel.user_in_channel?(sender).should be_false
  end

  it "joins a user to a password-protected channel with correct password" do
    sender = create_test_client("Alice")
    channel_name = "#protected"
    channel = Circed::Channel.new(channel_name)
    channel.add_mode("k", "secret")
    Circed::ChannelHandler.add_channel(channel)

    Circed::Actions::Join.call(sender, channel_name, "secret")

    channel.user_in_channel?(sender).should be_true
  end

  it "does not join a user to a password-protected channel with incorrect password" do
    sender = create_test_client("Alice")
    channel_name = "#protected"
    channel = Circed::Channel.new(channel_name)
    channel.add_mode("k", "secret")

    Circed::ChannelHandler.add_channel(channel)

    channel.user_in_channel?(sender).should be_false
    channel.channel_password.should eq("secret")

    Circed::Actions::Join.call(sender, channel_name, "wrong")

    channel.user_in_channel?(sender).should be_false
  end
end
