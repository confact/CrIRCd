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

  it "hides secret channels from non-members" do
    channel = Circed::Domain::Channel.new("#test")
    channel.modes << 's'
    channel.add_member("Alice")

    channel.visible_to?("Alice").should be_true
    channel.visible_to?("Bob").should be_false
    channel.visible_to?(nil).should be_false
  end

  it "hides private channels and keeps private and secret modes exclusive" do
    channel = Circed::Domain::Channel.new("#test")
    channel.add_member("Alice")
    channel.apply_modes("+p", [] of String)

    channel.visible_to?("Alice").should be_true
    channel.visible_to?("Bob").should be_false

    channel.apply_modes("+s", [] of String)
    channel.private?.should be_false
    channel.secret?.should be_true
  end

  it "should be able to manage user modes in channel" do
    channel = Circed::Domain::Channel.new("#test")
    channel.add_member("Alice")
    channel.members["Alice"] << 'o' # Make operator
    channel.members["Alice"].should contain('o')
    # Note: operators method doesn't exist, but we can verify the user has 'o' mode
    channel.members["Alice"].should contain('o')
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

    2.times do
      channel.add_invite("Alice")
      channel.add_ban("Evil*")
    end

    channel.invite_list.should eq(Set{"alice"})
    channel.invited?("ALICE").should be_true
    channel.remove_invite("aLiCe").should be_true
    channel.ban_list.should eq(Set{"Evil*"})
  end

  describe "ban matching" do
    it "matches standard hostmask bans with case-insensitive wildcards" do
      channel = Circed::Domain::Channel.new("#test")
      channel.add_ban("*!*@host.example")

      channel.banned?("Alice!alice@host.example").should be_true
      channel.banned?("Alice!alice@HOST.EXAMPLE").should be_true
      channel.banned?("Alice!alice@hostXexample").should be_false
    end

    it "matches extended bans against user fields" do
      channel = Circed::Domain::Channel.new("#test")
      context = Circed::Domain::BanMatchContext.new(
        "TroubleNick",
        "alice",
        "host.example",
        "192.0.2.10",
        "Blocked Realname",
        "TroubleNick!alice@host.example",
        ["#lobby"]
      )

      channel.add_ban("$n:Trouble*")
      channel.banned?(context).should be_true

      channel.remove_ban("$n:Trouble*")
      channel.add_ban("$u:ali?e")
      channel.banned?(context).should be_true

      channel.remove_ban("$u:ali?e")
      channel.add_ban("$h:host.example")
      channel.banned?(context).should be_true

      channel.remove_ban("$h:host.example")
      channel.add_ban("$r:*Realname")
      channel.banned?(context).should be_true
    end

    it "matches extended bans against joined channels and hostmask plus realname" do
      channel = Circed::Domain::Channel.new("#test")
      context = Circed::Domain::BanMatchContext.new(
        "Alice",
        "alice",
        "host.example",
        "192.0.2.10",
        "Blocked Realname",
        "Alice!alice@host.example",
        ["#holding", "#lobby"]
      )

      channel.add_ban("~j:#holding")
      channel.banned?(context).should be_true

      channel.remove_ban("~j:#holding")
      channel.add_ban("$x:Alice!*@host.example#Blocked*")
      channel.banned?(context).should be_true
    end

    it "ignores unsupported extended ban types" do
      channel = Circed::Domain::Channel.new("#test")
      context = Circed::Domain::BanMatchContext.new(
        "Alice",
        "alice",
        "host.example",
        "192.0.2.10",
        "Blocked Realname",
        "Alice!alice@host.example",
        ["#lobby"]
      )

      channel.add_ban("$a:*")
      channel.banned?(context).should be_false
    end
  end
end
