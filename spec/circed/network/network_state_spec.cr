require "../../spec_helper"

describe Circed::Network::NetworkState do
  before_each { clear_repositories }
  after_each { clear_repositories }

  it "persists scalar updates to stored structs" do
    Circed::Network::NetworkState.add_user("Alice", "alice", "host", "Alice", "remote")
    Circed::Network::NetworkState.set_user_away("Alice", "Gone")
    Circed::Network::NetworkState.get_user("Alice").try(&.away_message).should eq("Gone")

    Circed::Network::NetworkState.add_channel("#test")
    Circed::Network::NetworkState.set_channel_topic("#test", "Topic", "Alice")
    channel = Circed::Network::NetworkState.get_channel("#test")
    channel.try(&.topic).should eq("Topic")
    channel.try(&.topic_set_by).should eq("Alice")
  end

  it "keeps the older user during nickname collisions" do
    newer = Time.unix(200)
    older = Time.unix(100)

    Circed::Network::NetworkState.add_user("Alice", "new", "new.host", "New", "new.server", 1, newer).should be_true
    Circed::Network::NetworkState.add_user("Alice", "old", "old.host", "Old", "old.server", 1, older).should be_true
    Circed::Network::NetworkState.add_user("Alice", "latest", "latest.host", "Latest", "latest.server", 1, Time.unix(300)).should be_false

    user = Circed::Network::NetworkState.get_user("Alice")
    user.try(&.username).should eq("old")
    user.try(&.connected_at).should eq(older)
  end

  it "uses the server name to break equal user timestamp ties" do
    timestamp = Time.unix(100)

    Circed::Network::NetworkState.add_user("Alice", "z", "host", "Z", "z.server", 1, timestamp).should be_true
    Circed::Network::NetworkState.add_user("Alice", "a", "host", "A", "a.server", 1, timestamp).should be_true

    Circed::Network::NetworkState.get_user("Alice").try(&.server).should eq("a.server")
  end

  it "reserves nicknames briefly after removal" do
    Circed::Network::NetworkState.add_user("Alice", "alice", "host", "Alice", "remote").should be_true
    Circed::Network::NetworkState.remove_user("Alice")

    Circed::Network::NetworkState.nickname_reserved?("Alice").should be_true
  end

  it "uses IRC case mapping for users, channels, and memberships" do
    Circed::Network::NetworkState.add_user("Alice[One]", "alice", "host", "Alice", "remote").should be_true
    Circed::Network::NetworkState.add_channel("#Mixed[Case]")
    Circed::Network::NetworkState.join_user_to_channel("Alice[One]", "#Mixed[Case]")

    Circed::Network::NetworkState.get_user("aLICE{oNE}").try(&.nickname).should eq("Alice[One]")
    channel = Circed::Network::NetworkState.get_channel("#mIXED{cASE}")
    channel.try(&.name).should eq("#Mixed[Case]")
    channel.try(&.has_member?("ALICE{ONE}")).should be_true

    Circed::Network::NetworkState.part_user_from_channel("alice{one}", "#MIXED{CASE}")
    Circed::Network::NetworkState.get_channel("#Mixed[Case]").should be_nil
  end

  it "keeps modes from the older channel incarnation" do
    Circed::Network::NetworkState.merge_channel("#test", Time.unix(200), Set{'n'}).should be_true
    Circed::Network::NetworkState.join_user_to_channel("Alice", "#test", Set{'o'})

    Circed::Network::NetworkState.merge_channel("#test", Time.unix(100), Set{'m'}).should be_true
    channel = Circed::Network::NetworkState.get_channel("#test")
    channel.try(&.created_at).should eq(Time.unix(100))
    channel.try(&.modes).should eq(Set{'m'})
    channel.try(&.members["Alice"]).should eq(Set(Char).new)

    Circed::Network::NetworkState.merge_channel("#test", Time.unix(300), Set{'s'}).should be_false
    channel.try(&.modes).should eq(Set{'m'})
  end

  it "accepts topics only for the winning channel incarnation" do
    Circed::Network::NetworkState.merge_channel("#test", Time.unix(100), Set(Char).new)

    Circed::Network::NetworkState.set_channel_topic(
      "#test", "Current", "Alice", Time.unix(200), Time.unix(100)
    ).should be_true
    Circed::Network::NetworkState.set_channel_topic(
      "#test", "Wrong channel", "Bob", Time.unix(300), Time.unix(150)
    ).should be_false
    Circed::Network::NetworkState.set_channel_topic(
      "#test", "Older topic", "Bob", Time.unix(150), Time.unix(100)
    ).should be_false

    Circed::Network::NetworkState.get_channel("#test").try(&.topic).should eq("Current")
  end

  it "applies parameter modes only to the matching channel incarnation" do
    timestamp = Time.unix(100)
    Circed::Network::NetworkState.merge_channel("#test", timestamp, Set(Char).new)

    Circed::Network::NetworkState.apply_channel_modes(
      "#test", "+klb", ["ignored", "secret", "25", "*!*@blocked"], timestamp, 1
    ).should be_true
    Circed::Network::NetworkState.apply_channel_modes(
      "#test", "+k", ["wrong"], Time.unix(200)
    ).should be_false

    channel = Circed::Network::NetworkState.get_channel("#test")
    channel.try(&.password).should eq("secret")
    channel.try(&.user_limit).should eq(25)
    channel.try(&.ban_list).should eq(Set{"*!*@blocked"})

    repository_channel = Circed::Infrastructure::ServiceLocator.channel_repository["#test"]?
    repository_channel.try(&.password).should eq("secret")
    repository_channel.try(&.user_limit).should eq(25)
    repository_channel.try(&.ban_list).should eq(Set{"*!*@blocked"})
  end
end
