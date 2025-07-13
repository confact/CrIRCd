require "../../spec_helper"

describe Circed::Actions::Topic do
  before_each do
    clear_repositories
  end

  after_each do
    clear_repositories
  end

  it "sets a channel topic by an operator" do
    sender = create_test_client("Alice")
    channel_name = "#test"

    # Add user to channel (first user gets operator status)
    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(sender.nickname.to_s)
    domain_channel.members[sender.nickname.to_s] << 'o' # Make first user operator

    new_topic = "new topic"
    Circed::Actions::Topic.call(sender, [channel_name, new_topic])

    # Check domain channel directly
    channel = get_test_channel(channel_name).not_nil!
    channel.topic.should eq(new_topic)
    channel.topic_set_by.should eq("Alice")
    channel.topic_set_at.should_not be_nil
  end

  it "topic setter presist even after user left channel" do
    sender = create_test_client("Alice")
    other_user = create_test_client("Bob")
    channel_name = "#test"

    # Add users to channel
    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(sender.nickname.to_s)
    domain_channel.members[sender.nickname.to_s] << 'o' # Make first user operator
    domain_channel.add_member(other_user.nickname.to_s)

    new_topic = "new topic"
    Circed::Actions::Topic.call(sender, [channel_name, new_topic])

    # Remove sender from channel
    domain_channel.remove_member(sender.nickname.to_s)

    # Topic should persist
    channel = get_test_channel(channel_name).not_nil!
    channel.topic.should eq(new_topic)
    channel.topic_set_by.should eq("Alice")
    channel.topic_set_at.should_not be_nil
  end

  it "topic setter presist even if user left server" do
    sender = create_test_client("Alice")
    other_user = create_test_client("Bob")
    channel_name = "#test"

    # Add users to channel
    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(sender.nickname.to_s)
    domain_channel.members[sender.nickname.to_s] << 'o' # Make first user operator
    domain_channel.add_member(other_user.nickname.to_s)

    new_topic = "new topic"
    Circed::Actions::Topic.call(sender, [channel_name, new_topic])

    # Remove user from server
    user_repository.remove_client(sender.nickname.not_nil!)

    # Topic should persist
    channel = get_test_channel(channel_name).not_nil!
    channel.topic.should eq(new_topic)
    channel.topic_set_by.should eq("Alice")
    channel.topic_set_at.should_not be_nil
  end

  it "returns an error when a non-operator sets a topic" do
    sender = create_test_client("Alice")
    other_user = create_test_client("Bob")
    channel_name = "#test"

    # Add Bob first (gets operator), then Alice (doesn't get operator)
    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(other_user.nickname.to_s)
    domain_channel.add_member(sender.nickname.to_s)

    new_topic = "new topic"
    Circed::Actions::Topic.call(sender, [channel_name, new_topic])

    # Topic should not be changed since Alice is not an operator
    channel = get_test_channel(channel_name).not_nil!
    channel.topic.should_not eq(new_topic)
    channel.topic_set_by.should be_nil
    channel.topic_set_at.should be_nil
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

    # Create empty channel (no users)
    create_test_channel(channel_name)

    Circed::Actions::Topic.call(sender, [channel_name, "new topic"])

    # Topic should not be set
    channel = get_test_channel(channel_name).not_nil!
    channel.topic.should_not eq("new topic")
    channel.topic_set_by.should be_nil
    channel.topic_set_at.should be_nil
  end
end
