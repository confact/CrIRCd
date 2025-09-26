require "../../spec_helper"

describe Circed::Actions::Part do
  before_each do
    clear_repositories
  end

  after_each do
    clear_repositories
  end

  it "parts a user from a channel" do
    sender = create_test_client("Alice")
    channel_name = "#test"
    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(sender.nickname.to_s)

    Circed::Actions::Part.call(sender, channel_name)

    is_user_in_channel?(channel_name, sender.nickname.to_s).should be_false
    channel_empty?(channel_name).should be_true
  end

  it "does not part a user from a non-existing channel" do
    sender = create_test_client("Alice")
    channel_name = "#nonexist"

    Circed::Actions::Part.call(sender, channel_name)

    is_user_in_channel?(channel_name, sender.nickname.to_s).should be_false
    channel_empty?(channel_name).should be_true
  end

  it "does not part a user who is not a member of the channel" do
    sender = create_test_client("Alice")
    other_user = create_test_client("Bob")
    channel_name = "#test"
    domain_channel = create_test_channel(channel_name)
    domain_channel.add_member(other_user.nickname.to_s)

    Circed::Actions::Part.call(sender, channel_name)

    is_user_in_channel?(channel_name, sender.nickname.to_s).should be_false
    channel_empty?(channel_name).should be_false
  end
end
