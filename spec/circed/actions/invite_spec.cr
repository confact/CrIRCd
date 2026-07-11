require "../../spec_helper"

describe Circed::Actions::Invite do
  before_each do
    clear_repositories
  end

  after_each do
    clear_repositories
  end

  it "allows invites to a channel that does not exist yet" do
    sender = create_test_client("Alice")
    invited = create_test_client("Bob")

    Circed::Actions::Invite.call(sender, "Bob", "#new")

    sender.socket.as(DummySocket).sent_data.join.should contain(" 341 Alice Bob #new")
    invited.socket.as(DummySocket).sent_data.join.should contain(" INVITE Bob #new")
  end

  it "requires an operator to invite into an invite-only channel" do
    sender = create_test_client("Alice")
    invited = create_test_client("Bob")
    channel = create_test_channel("#invite-only")
    channel.add_member("Alice")
    channel.modes << 'i'

    Circed::Actions::Invite.call(sender, "Bob", "#invite-only")

    sender.socket.as(DummySocket).sent_data.join.should contain(" 482 Alice #invite-only")
    invited.socket.as(DummySocket).sent_data.join.should_not contain(" INVITE Bob #invite-only")
  end

  it "records an invite from an operator for an invite-only channel" do
    sender = create_test_client("Alice")
    invited = create_test_client("Bob")
    channel = create_test_channel("#invite-only")
    channel.add_member("Alice")
    channel.members["Alice"] << 'o'
    channel.modes << 'i'

    Circed::Actions::Invite.call(sender, "Bob", "#invite-only")

    channel.invited?("Bob").should be_true
    invited.socket.as(DummySocket).sent_data.join.should contain(" INVITE Bob #invite-only")
  end

  it "reports the invited user's away status" do
    sender = create_test_client("Alice")
    create_test_client("Bob")
    user_repository["Bob"]?.try(&.away_message = "Lunch")

    Circed::Actions::Invite.call(sender, "Bob", "#new")

    sender.socket.as(DummySocket).sent_data.join.should contain(" 301 Alice Bob Lunch")
  end
end
