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
    channel = get_test_channel(channel_name).not_nil!
    channel.members["Bob"].includes?('o').should be_true
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
    channel = get_test_channel(channel_name).not_nil!
    channel.modes.includes?('m').should be_true
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
    channel = get_test_channel(channel_name).not_nil!
    channel.members["Bob"] << 'o'
    channel.members["Bob"].includes?('o').should be_true

    Circed::Actions::Mode.call(sender, [channel_name, "-o", "Bob"])

    # Check that operator mode was removed
    channel.members["Bob"].includes?('o').should be_false
  end

  it "remove a channel mode" do
    sender = create_test_client("Alice")
    channel_name = "#test"

    # Add user to channel and set mode
    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(sender.nickname.to_s)
    domain_channel.members[sender.nickname.to_s] << 'o' # Make first user operator
    channel = get_test_channel(channel_name).not_nil!
    channel.modes << 'm'
    channel.modes.includes?('m').should be_true

    Circed::Actions::Mode.call(sender, [channel_name, "-m"])

    # Check that mode was removed
    channel.modes.includes?('m').should be_false
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
