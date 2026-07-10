require "../../spec_helper"

describe Circed::Actions::Join do
  before_each do
    clear_repositories
  end

  after_each do
    clear_repositories
  end

  it "joins a user to a channel" do
    sender = create_test_client("Alice")
    channel_name = "#test"

    Circed::Actions::Join.call(sender, channel_name)

    # Check that user is in channel
    user_in_channel?(channel_name, "Alice").should be_true

    # Check domain channel directly
    channel = get_test_channel(channel_name)
    channel.should_not be_nil
    channel.try(&.has_member?("Alice")).should be_true
  end

  it "does not join a user to a private channel" do
    sender = create_test_client("Alice")
    channel_name = "#private"

    # Create invite-only channel
    domain_channel = create_test_channel(channel_name)
    domain_channel.modes << 'i' # Make invite-only

    Circed::Actions::Join.call(sender, channel_name)

    user_in_channel?(channel_name, "Alice").should be_false
  end

  it "joins a user to a password-protected channel with correct password" do
    sender = create_test_client("Alice")
    channel_name = "#protected"

    # Create password-protected channel
    domain_channel = create_test_channel(channel_name)
    domain_channel.password = "secret"

    Circed::Actions::Join.call(sender, channel_name, "secret")

    user_in_channel?(channel_name, "Alice").should be_true
  end

  it "does not join a user to a password-protected channel with incorrect password" do
    sender = create_test_client("Alice")
    channel_name = "#protected"

    # Create password-protected channel
    domain_channel = create_test_channel(channel_name)
    domain_channel.password = "secret"

    # Initially not in channel
    user_in_channel?(channel_name, "Alice").should be_false

    Circed::Actions::Join.call(sender, channel_name, "wrong")

    # Should still not be in channel due to password validation
    user_in_channel?(channel_name, "Alice").should be_false
  end

  it "consumes an invitation after a successful join" do
    sender = create_test_client("Alice")
    channel = create_test_channel("#invite-only")
    channel.modes << 'i'
    channel.add_invite("Alice")

    Circed::Actions::Join.call(sender, "#invite-only")

    channel.has_member?("Alice").should be_true
    channel.invited?("Alice").should be_false
  end
end
