require "../../spec_helper"

describe Circed::Actions::Part do
  before_each do
    Circed::UserHandler.clear
    Circed::ChannelHandler.clear
  end

  after_each do
    Circed::UserHandler.clear
    Circed::ChannelHandler.clear
  end

  it "parts a user from a channel" do
    sender = create_test_client("Alice")
    channel_name = "#test"
    Circed::ChannelHandler.add_user_to_channel(channel_name, sender)

    Circed::Actions::Part.call(sender, channel_name)

    Circed::ChannelHandler.user_in_channel?(channel_name, sender).should be_false
    Circed::ChannelHandler.channel_empty?(channel_name).should be_true
  end

  it "does not part a user from a non-existing channel" do
    sender = create_test_client("Alice")
    channel_name = "#nonexist"

    Circed::Actions::Part.call(sender, channel_name)

    Circed::ChannelHandler.user_in_channel?(channel_name, sender).should be_false
    Circed::ChannelHandler.channel_empty?(channel_name).should be_true
  end

  it "does not part a user who is not a member of the channel" do
    sender = create_test_client("Alice")
    other_user = create_test_client("Bob")
    channel_name = "#test"
    Circed::ChannelHandler.add_user_to_channel(channel_name, other_user)

    Circed::Actions::Part.call(sender, channel_name)

    Circed::ChannelHandler.user_in_channel?(channel_name, sender).should be_false
    Circed::ChannelHandler.channel_empty?(channel_name).should be_false
  end
end