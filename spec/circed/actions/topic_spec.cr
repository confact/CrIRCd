require "../../spec_helper"

describe Circed::Actions::Topic do
  before_each do
    Circed::UserHandler.clear
    Circed::ChannelHandler.clear
  end

  after_each do
    Circed::UserHandler.clear
    Circed::ChannelHandler.clear
  end

  it "sets a channel topic by an operator" do
    sender = create_test_client("Alice")
    channel_name = "#test"
    channel = Circed::Channel.new(channel_name)
    channel.add_client(sender)
    Circed::ChannelHandler.add_channel(channel)

    new_topic = "new topic"
    Circed::Actions::Topic.call(sender, [channel_name, new_topic])

    channel.topic.should eq(new_topic)
    channel.topic_setter.should eq(channel.find_user(sender))
    channel.topic_set_at.should_not be_nil
  end

  it "topic setter presist even after user left channel" do
    sender = create_test_client("Alice")
    other_user = create_test_client("Bob")
    channel_name = "#test"
    channel = Circed::Channel.new(channel_name)
    channel.add_client(sender)
    channel.add_client(other_user)
    Circed::ChannelHandler.add_channel(channel)

    new_topic = "new topic"
    Circed::Actions::Topic.call(sender, [channel_name, new_topic])
    channel.remove_client(sender)

    channel.topic.should eq(new_topic)
    channel.topic_setter.should_not be_nil
    channel.topic_set_at.should_not be_nil
  end

  it "topic setter presist even if user left server" do
    sender = create_test_client("Alice")
    other_user = create_test_client("Bob")
    channel_name = "#test"
    channel = Circed::Channel.new(channel_name)
    channel.add_client(sender)
    channel.add_client(other_user)
    Circed::ChannelHandler.add_channel(channel)

    new_topic = "new topic"
    Circed::Actions::Topic.call(sender, [channel_name, new_topic])
    Circed::UserHandler.remove_connection(sender.nickname.not_nil!)

    channel.topic.should eq(new_topic)
    channel.topic_setter.should_not be_nil
    channel.topic_set_at.should_not be_nil
  end

  it "returns an error when a non-operator sets a topic" do
    sender = create_test_client("Alice")
    other_user = create_test_client("Bob")
    channel_name = "#test"
    channel = Circed::Channel.new(channel_name)
    channel.add_client(other_user)
    channel.add_client(sender)
    Circed::ChannelHandler.add_channel(channel)

    new_topic = "new topic"
    Circed::Actions::Topic.call(sender, [channel_name, new_topic])

    channel.topic.should_not eq(new_topic)
    channel.topic_setter.should be_nil
    channel.topic_set_at.should be_nil

    # sender.socket.received_errors.should include({error: Numerics::ERR_CHANOPRIVSNEEDED, message: "You're not an operator on that channel"})
  end

  it "returns an error for an invalid channel" do
    sender = create_test_client("Alice")
    invalid_channel_name = "#nonexistent"

    Circed::Actions::Topic.call(sender, [invalid_channel_name, "new topic"])

    # sender.socket.received_errors.should include({error: Numerics::ERR_NOSUCHCHANNEL, message: "No such channel"})
  end

  it "returns an error if a user is not in the channel" do
    sender = create_test_client("Alice")
    channel_name = "#test"
    channel = Circed::Channel.new(channel_name)
    Circed::ChannelHandler.add_channel(channel)

    Circed::Actions::Topic.call(sender, [channel_name, "new topic"])

    channel.topic.should_not eq("new topic")
    channel.topic_setter.should be_nil
    channel.topic_set_at.should be_nil

    # sender.socket.received_errors.should include({error: Numerics::ERR_NOTONCHANNEL, message: "You're not on that channel"})
  end
end
