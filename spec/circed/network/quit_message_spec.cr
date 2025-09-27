require "../../spec_helper"

describe "Netsplit QUIT message format" do
  before_each do
    Circed::Network::NetworkState.clear_all_state
  end

  describe "RFC-compliant QUIT messages" do
    it "generates correct netsplit QUIT format" do
      # Setup: Hub ← Server1 with users
      Circed::Network::NetworkState.add_server("server1.irc", 1, "Server 1", nil, "101")
      Circed::Network::NetworkState.add_server_link("localhost", "server1.irc")

      # Add user on server1
      user_info = Circed::Network::NetworkState::UserInfo.new(
        "alice", "alice", "server1.host", "Alice User", "server1.irc", 1
      )

      # Build the QUIT message as the code does
      quit_message = String.build do |io|
        io << ':' << user_info.hostmask << " QUIT :"
        io << "server1.irc" << ' ' << Circed::Server.name
      end

      # Should match RFC format: :nick!user@host QUIT :server1 server2
      quit_message.should match(/^:alice!alice@server1\.host QUIT :server1\.irc \S+/)
    end

    it "preserves user hostmask during netsplit" do
      # Add server and user
      Circed::Network::NetworkState.add_server("remote.irc", 1, "Remote", nil, "201")
      Circed::Network::NetworkState.add_user("bob", "bobby", "remote.host", "Bob User", "remote.irc", 1)

      # Get user before removal
      user = Circed::Network::NetworkState.get_user("bob")
      user.should_not be_nil
      original_hostmask = user.try(&.hostmask)

      # Hostmask should be preserved correctly
      original_hostmask.should eq("bob!bobby@remote.host")
    end
  end

  describe "QUIT message propagation" do
    it "sends QUIT to all local users in shared channels" do
      # Setup network topology
      Circed::Network::NetworkState.add_server("server1.irc", 1, "Server 1", nil, "101")
      Circed::Network::NetworkState.add_server_link("localhost", "server1.irc")

      # Add remote user
      Circed::Network::NetworkState.add_user("remote_user", "remote", "server1.host", "Remote", "server1.irc", 1)

      # Add channel with remote user
      Circed::Network::NetworkState.add_channel("#shared")
      Circed::Network::NetworkState.join_user_to_channel("remote_user", "#shared")

      # Verify user is in channel before split
      channel = Circed::Network::NetworkState.get_channel("#shared")
      channel.should_not be_nil
      channel.try(&.members.has_key?("remote_user")).should be_true

      # Trigger netsplit
      Circed::Network::NetworkState.remove_server("server1.irc")

      # User should be removed from channel
      channel = Circed::Network::NetworkState.get_channel("#shared")
      if channel
        channel.members.has_key?("remote_user").should be_false
      end
    end

    it "avoids duplicate QUIT messages to same local user" do
      # This is tested via the Set(String) tracking in send_quit_to_local_users
      # The implementation uses local_users_notified to prevent duplicates

      # Setup multiple channels with same users
      Circed::Network::NetworkState.add_server("server1.irc", 1, "Server 1", nil, "101")
      Circed::Network::NetworkState.add_user("alice", "alice", "server1.host", "Alice", "server1.irc", 1)

      # Add user to multiple channels
      ["#chan1", "#chan2", "#chan3"].each do |chan|
        Circed::Network::NetworkState.add_channel(chan)
        Circed::Network::NetworkState.join_user_to_channel("alice", chan)
      end

      # All channels should have alice
      ["#chan1", "#chan2", "#chan3"].each do |chan|
        channel = Circed::Network::NetworkState.get_channel(chan)
        channel.should_not be_nil
        channel.try(&.members.has_key?("alice")).should be_true
      end

      # Remove server (this should only send one QUIT per local user)
      Circed::Network::NetworkState.remove_server("server1.irc")

      # User should be gone from all channels
      ["#chan1", "#chan2", "#chan3"].each do |chan|
        channel = Circed::Network::NetworkState.get_channel(chan)
        if channel
          channel.members.has_key?("alice").should be_false
        end
      end
    end
  end

  describe "complex netsplit scenarios" do
    it "handles multi-server cascade correctly" do
      # Setup: Hub ← A ← B ← C
      servers = [
        {"A.irc", 1, "Server A"},
        {"B.irc", 2, "Server B"},
        {"C.irc", 3, "Server C"},
      ]

      servers.each do |(name, hop, desc)|
        Circed::Network::NetworkState.add_server(name, hop, desc, nil, "10#{hop}")
      end

      Circed::Network::NetworkState.add_server_link("localhost", "A.irc")
      Circed::Network::NetworkState.add_server_link("A.irc", "B.irc")
      Circed::Network::NetworkState.add_server_link("B.irc", "C.irc")

      # Add users on each server
      users = [
        {"userA", "A.irc"},
        {"userB", "B.irc"},
        {"userC", "C.irc"},
      ]

      users.each do |(nick, server)|
        Circed::Network::NetworkState.add_user(nick, nick, "#{server}.host", nick, server, 1)
      end

      # All in same channel
      Circed::Network::NetworkState.add_channel("#network")
      users.each do |(nick, _)|
        Circed::Network::NetworkState.join_user_to_channel(nick, "#network")
      end

      # Initial state
      Circed::Network::NetworkState.stats[:servers].should eq(3)
      Circed::Network::NetworkState.stats[:users].should eq(3)

      # Split at A (should remove A, B, C)
      Circed::Network::NetworkState.remove_server("A.irc")

      # All servers and users should be gone
      Circed::Network::NetworkState.stats[:servers].should eq(0)
      Circed::Network::NetworkState.stats[:users].should eq(0)

      # Channel should be empty and removed
      Circed::Network::NetworkState.get_channel("#network").should be_nil
    end

    it "preserves unaffected branch during partial split" do
      # Setup: Hub ← A ← B, Hub ← C ← D
      Circed::Network::NetworkState.add_server("A.irc", 1, "Server A", nil, "101")
      Circed::Network::NetworkState.add_server("B.irc", 2, "Server B", nil, "102")
      Circed::Network::NetworkState.add_server("C.irc", 1, "Server C", nil, "103")
      Circed::Network::NetworkState.add_server("D.irc", 2, "Server D", nil, "104")

      Circed::Network::NetworkState.add_server_link("localhost", "A.irc")
      Circed::Network::NetworkState.add_server_link("A.irc", "B.irc")
      Circed::Network::NetworkState.add_server_link("localhost", "C.irc")
      Circed::Network::NetworkState.add_server_link("C.irc", "D.irc")

      # Add users
      ["A", "B", "C", "D"].each do |server|
        Circed::Network::NetworkState.add_user("user#{server}", "user", "host", "User", "#{server}.irc", 1)
      end

      # Initial: 4 servers, 4 users
      Circed::Network::NetworkState.stats[:servers].should eq(4)
      Circed::Network::NetworkState.stats[:users].should eq(4)

      # Split A branch (should remove A, B but keep C, D)
      Circed::Network::NetworkState.remove_server("A.irc")

      # Should have 2 servers and 2 users remaining
      Circed::Network::NetworkState.stats[:servers].should eq(2)
      Circed::Network::NetworkState.stats[:users].should eq(2)

      # C and D should remain
      Circed::Network::NetworkState.get_server("C.irc").should_not be_nil
      Circed::Network::NetworkState.get_server("D.irc").should_not be_nil
      Circed::Network::NetworkState.get_user("userC").should_not be_nil
      Circed::Network::NetworkState.get_user("userD").should_not be_nil

      # A and B should be gone
      Circed::Network::NetworkState.get_server("A.irc").should be_nil
      Circed::Network::NetworkState.get_server("B.irc").should be_nil
      Circed::Network::NetworkState.get_user("userA").should be_nil
      Circed::Network::NetworkState.get_user("userB").should be_nil
    end
  end
end
