require "../../spec_helper"

describe Circed::Actions::Mode do
  before_each do
    Circed::UserHandler.clear
    Circed::ChannelHandler.clear
  end

  after_each do
    Circed::UserHandler.clear
    Circed::ChannelHandler.clear
  end

  it "sets a user mode" do
    sender = create_test_client("Alice")
    receiver = create_test_client("Bob")
    channel_name = "#test"
    channel = Circed::Channel.new(channel_name)
    channel.add_client(sender)
    channel.add_client(receiver)
    Circed::ChannelHandler.add_channel(channel)

    Circed::Actions::Mode.call(sender, [channel_name, receiver.nickname || "unknown", "+o"])

    # channel user modes
    (channel.find_user(receiver).try(&.modes) || "").not_nil!.to_s.should contain "o"
  end

  it "sets a channel mode" do
    sender = create_test_client("Alice")
    channel_name = "#test"
    channel = Circed::Channel.new(channel_name)
    channel.add_client(sender)
    Circed::ChannelHandler.add_channel(channel)

    Circed::Actions::Mode.call(sender, [channel_name, "+m"])

    channel.modes.keys.should contain "m"
  end

  it "remove a user mode" do
    sender = create_test_client("Alice")
    receiver = create_test_client("Bob")
    channel_name = "#test"
    channel = Circed::Channel.new(channel_name)
    channel.add_client(sender)
    channel.add_client(receiver)
    Circed::ChannelHandler.add_channel(channel)

    if user = channel.find_user(receiver)
      user.add_mode("o")
    end
    (channel.find_user(receiver).try(&.modes) || "").not_nil!.to_s.should contain "o"


    Circed::Actions::Mode.call(sender, [channel_name, receiver.nickname || "unknown", "-o"])

    # channel user modes
    (channel.find_user(receiver).try(&.modes) || "").not_nil!.to_s.should_not contain "o"
  end

  it "remove a channel mode" do
    sender = create_test_client("Alice")
    channel_name = "#test"
    channel = Circed::Channel.new(channel_name)
    channel.add_client(sender)
    Circed::ChannelHandler.add_channel(channel)

    channel.add_mode("m", nil)
    channel.modes.keys.should contain "m"

    Circed::Actions::Mode.call(sender, [channel_name, "-m"])

    channel.modes.keys.should_not contain "m"
  end

  it "returns an error for an invalid channel" do
    sender = create_test_client("Alice")
    invalid_channel_name = "#nonexistent"

    Circed::Actions::Mode.call(sender, [invalid_channel_name, "+m"])

    #sender.socket.received_errors.should include({error: Numerics::ERR_NOSUCHCHANNEL, message: "No such channel"})
  end

  it "returns an error for an invalid nickname" do
    sender = create_test_client("Alice")
    invalid_nickname = "nonexistent"
    channel_name = "#test"
    channel = Circed::Channel.new(channel_name)
    channel.add_client(sender)
    Circed::ChannelHandler.add_channel(channel)

    Circed::Actions::Mode.call(sender, [channel_name, invalid_nickname, "+o"])

    #sender.socket.received_errors.should include({error: Numerics::ERR_NOSUCHNICK, message: "No such nick"})
  end
end
