require "../../spec_helper"

describe Circed::Domain::Channel do
  it "should be able to create a new channel" do
    channel = Circed::Domain::Channel.new("#test")
    channel.should be_a(Circed::Domain::Channel)
  end

  it "should be able to create a new channel with a name" do
    channel = Circed::Domain::Channel.new("#test")
    channel.should be_a(Circed::Domain::Channel)
    channel.name.should eq("#test")
  end

  it "should be able to create a new channel with empty members" do
    channel = Circed::Domain::Channel.new("#test")
    channel.should be_a(Circed::Domain::Channel)
    channel.name.should eq("#test")
    channel.empty?.should be_true
    channel.member_count.should eq(0)
  end

  it "should be able to add users to a channel" do
    channel = Circed::Domain::Channel.new("#test")
    channel.add_member("Alice")
    channel.empty?.should be_false
    channel.has_member?("Alice").should be_true
    channel.member_count.should eq(1)
  end

  it "should be able to remove users from a channel" do
    channel = Circed::Domain::Channel.new("#test")
    channel.add_member("Alice")
    channel.empty?.should be_false
    channel.has_member?("Alice").should be_true
    channel.remove_member("Alice")
    channel.empty?.should be_true
    channel.has_member?("Alice").should be_false
  end

  it "should be able to manage channel modes" do
    channel = Circed::Domain::Channel.new("#test")
    channel.modes.should be_empty
    channel.modes << 's'
    channel.modes.should contain('s')
  end

  it "should be able to manage user modes in channel" do
    channel = Circed::Domain::Channel.new("#test")
    channel.add_member("Alice")
    channel.members["Alice"] << 'o' # Make operator
    channel.members["Alice"].should contain('o')
    # Note: operators method doesn't exist, but we can verify the user has 'o' mode
    channel.user_modes("Alice").should contain('o')
  end

  it "should be able to manage topic" do
    channel = Circed::Domain::Channel.new("#test")
    channel.topic.should be_nil
    channel.topic = "Test topic"
    channel.topic_set_by = "Alice"
    channel.topic_set_at = Time.utc
    channel.topic.should eq("Test topic")
    channel.topic_set_by.should eq("Alice")
    channel.topic_set_at.should be_a(Time)
  end

  it "should be able to manage invite and ban lists" do
    channel = Circed::Domain::Channel.new("#test")
    channel.invite_list.should be_empty
    channel.ban_list.should be_empty

    channel.invite_list << "Alice"
    channel.ban_list << "Evil*"

    channel.invite_list.should contain("Alice")
    channel.ban_list.should contain("Evil*")
  end
end
