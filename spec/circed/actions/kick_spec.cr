describe Circed::Actions::Kick do
  before_each do
    # Initialize and set up your mocks
    clear_repositories
  end

  after_each do
    # Clean up your mocks
    clear_repositories
  end

  it "kicks a user from a channel" do
    sender = create_test_client("Alice")
    kicked_user = create_test_client("Bob")

    # Create channel and add users through handler
    channel_name = "#test"
    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(sender.nickname.to_s)
    domain_channel.add_member(kicked_user.nickname.to_s)

    # Make sender an operator
    domain_channel = get_test_channel(channel_name)
    next unless domain_channel
    domain_channel.members["Alice"] << 'o'

    # Call the kick action
    Circed::Actions::Kick.call(sender, ["#test", "Bob", "testing kick"])

    # Verify Bob was kicked
    user_in_channel?(channel_name, kicked_user.nickname.to_s).should be_false
  end

  it "does not kick a user if sender is not an operator" do
    sender = create_test_client("Alice")
    kicked_user = create_test_client("Bob")

    # Create channel and add users
    channel_name = "#test"
    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(sender.nickname.to_s)
    domain_channel.add_member(kicked_user.nickname.to_s)

    # Don't make sender an operator (first user gets op by default, so remove it)
    domain_channel = get_test_channel(channel_name)
    next unless domain_channel
    domain_channel.members["Alice"].delete('o')

    # Verify sender is in channel but not an operator
    user_in_channel?(channel_name, sender.nickname.to_s).should be_true
    domain_channel.members["Alice"].includes?('o').should be_false

    # Call the kick action
    Circed::Actions::Kick.call(sender, ["#test", "Bob", "testing kick"])

    # Bob should still be in channel since Alice is not an operator
    user_in_channel?(channel_name, kicked_user.nickname.to_s).should be_true
  end

  it "kicks multiple users from one channel" do
    sender = create_test_client("Alice")
    create_test_client("Bob")
    create_test_client("Carol")

    channel_name = "#test"
    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member("Alice")
    domain_channel.members["Alice"] << 'o'
    domain_channel.add_member("Bob")
    domain_channel.add_member("Carol")

    Circed::Actions::Kick.call(sender, ["#test", "Bob,Carol", "cleanup"])

    user_in_channel?(channel_name, "Bob").should be_false
    user_in_channel?(channel_name, "Carol").should be_false
  end

  it "uses ERR_USERNOTINCHANNEL when the target is absent" do
    sender = create_test_client("Alice")
    create_test_client("Bob")
    channel = create_test_channel("#test")
    channel.add_member("Alice")
    channel.members["Alice"] << 'o'

    Circed::Actions::Kick.call(sender, ["#test", "Bob"])

    sender.socket.as(DummySocket).sent_data.join.should contain(" 441 Alice Bob #test :They aren't on that channel")
  end
end
