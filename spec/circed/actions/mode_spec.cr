require "../../spec_helper"

describe Circed::Actions::Mode do
  before_each do
    clear_repositories
  end

  after_each do
    clear_repositories
  end

  it "sets a user mode" do
    sender = create_test_client("Alice")
    receiver = create_test_client("Bob")
    channel_name = "#test"

    # Add users to channel (Alice gets operator)
    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(sender.nickname.to_s)
    domain_channel.members[sender.nickname.to_s] << 'o' # Make first user operator
    domain_channel.add_member(receiver.nickname.to_s)

    Circed::Actions::Mode.call(sender, [channel_name, "+o", "Bob"])

    # Check user modes in domain channel
    channel = get_test_channel(channel_name)
    channel.should_not be_nil
    channel.try(&.members["Bob"].includes?('o')).should be_true
  end

  it "accepts RFC1459-equivalent casing for a user's own modes" do
    sender = create_test_client("Alice[One]")

    Circed::Actions::Mode.call(sender, ["aLICE{oNE}", "+i"])

    user_repository["Alice[One]"]?.try(&.modes.includes?('i')).should be_true
  end

  it "sets a channel mode" do
    sender = create_test_client("Alice")
    channel_name = "#test"

    # Add user to channel (gets operator)
    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(sender.nickname.to_s)
    domain_channel.members[sender.nickname.to_s] << 'o' # Make first user operator

    Circed::Actions::Mode.call(sender, [channel_name, "+m"])

    # Check channel modes in domain channel
    channel = get_test_channel(channel_name)
    channel.should_not be_nil
    channel.try(&.modes.includes?('m')).should be_true
  end

  it "sets and removes a channel ban mask" do
    sender = create_test_client("Alice")
    channel_name = "#test"

    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(sender.nickname.to_s)
    domain_channel.members[sender.nickname.to_s] << 'o'

    Circed::Actions::Mode.call(sender, [channel_name, "+b", "*!*@localhost"])

    channel = get_test_channel(channel_name)
    channel.should_not be_nil
    if ch = channel
      ch.ban_list.should contain("*!*@localhost")
      ch.modes.includes?('b').should be_true
    end

    Circed::Actions::Mode.call(sender, [channel_name, "-b", "*!*@localhost"])

    if ch = channel
      ch.ban_list.should be_empty
      ch.modes.includes?('b').should be_false
    end
  end

  it "sets key and user limit channel modes" do
    sender = create_test_client("Alice")
    channel_name = "#test"

    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(sender.nickname.to_s)
    domain_channel.members[sender.nickname.to_s] << 'o'

    Circed::Actions::Mode.call(sender, [channel_name, "+kl", "secret", "25"])

    channel = get_test_channel(channel_name)
    channel.should_not be_nil
    if ch = channel
      ch.password.should eq("secret")
      ch.user_limit.should eq(25)
      ch.modes.includes?('k').should be_true
      ch.modes.includes?('l').should be_true
    end
  end

  it "returns channel modes for a mode query" do
    sender = create_test_client("Alice")
    channel_name = "#test"

    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(sender.nickname.to_s)
    domain_channel.members[sender.nickname.to_s] << 'o'
    domain_channel.modes << 's'
    domain_channel.password = "secret"
    domain_channel.user_limit = 10

    Circed::Actions::Mode.call(sender, [channel_name])

    socket = sender.socket.as(DummySocket)
    socket.sent_data.join.should contain(" 324 Alice #test +skl secret 10")
    socket.sent_data.join.should contain(" 329 Alice #test ")
  end

  it "remove a user mode" do
    sender = create_test_client("Alice")
    receiver = create_test_client("Bob")
    channel_name = "#test"

    # Add users to channel
    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(sender.nickname.to_s)
    domain_channel.members[sender.nickname.to_s] << 'o' # Make first user operator
    domain_channel.add_member(receiver.nickname.to_s)

    # Give Bob operator status
    channel = get_test_channel(channel_name)
    channel.should_not be_nil
    if ch = channel
      ch.members["Bob"] << 'o'
      ch.members["Bob"].includes?('o').should be_true
    end

    Circed::Actions::Mode.call(sender, [channel_name, "-o", "Bob"])

    # Check that operator mode was removed
    if ch = channel
      ch.members["Bob"].includes?('o').should be_false
    end
  end

  it "remove a channel mode" do
    sender = create_test_client("Alice")
    channel_name = "#test"

    # Add user to channel and set mode
    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(sender.nickname.to_s)
    domain_channel.members[sender.nickname.to_s] << 'o' # Make first user operator
    channel = get_test_channel(channel_name)
    channel.should_not be_nil
    if ch = channel
      ch.modes << 'm'
      ch.modes.includes?('m').should be_true
    end

    Circed::Actions::Mode.call(sender, [channel_name, "-m"])

    # Check that mode was removed
    if ch = channel
      ch.modes.includes?('m').should be_false
    end
  end

  it "returns an error for an invalid channel" do
    sender = create_test_client("Alice")
    invalid_channel_name = "#nonexistent"

    Circed::Actions::Mode.call(sender, [invalid_channel_name, "+m"])

    # sender.socket.received_errors.should include({error: Numerics::ERR_NOSUCHCHANNEL, message: "No such channel"})
  end

  it "returns an error for an invalid nickname" do
    sender = create_test_client("Alice")
    invalid_nickname = "nonexistent"
    channel_name = "#test"

    # Add sender to channel
    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(sender.nickname.to_s)
    domain_channel.members[sender.nickname.to_s] << 'o' # Make first user operator

    Circed::Actions::Mode.call(sender, [channel_name, "+o", invalid_nickname])

    # The action should handle the invalid nickname gracefully
    # No exception should be thrown
  end
end
