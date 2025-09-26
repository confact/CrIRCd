require "../../spec_helper"

# Mock LinkServer for testing
class MockLinkServer < Circed::LinkServer
  getter sent_messages : Array(String) = [] of String

  def initialize(@name : String)
    @target_host = "mock.host"
    @target_port = 6667
    @socket = nil
  end

  def safe_send(message : String) : Nil
    @sent_messages << message
  end

  def clear_messages
    @sent_messages.clear
  end
end

describe Circed::Network::BurstProtocol do
  before_each do
    Circed::Network::NetworkState.clear_all_state
  end

  describe "send_burst" do
    it "sends complete network state to new server" do
      mock_server = MockLinkServer.new("new.irc")

      # Setup network state
      Circed::Network::NetworkState.add_server("existing.irc", 1, "Existing Server", nil, "201")
      Circed::Network::NetworkState.add_user("alice", "alice", "host.com", "Alice User", "existing.irc", 1)
      Circed::Network::NetworkState.add_channel("#test")
      Circed::Network::NetworkState.join_user_to_channel("alice", "#test", Set{'o'})

      # Send burst
      Circed::Network::BurstProtocol.send_burst(mock_server)

      # Check messages sent
      messages = mock_server.sent_messages

      # Should send servers
      messages.any?(&.starts_with?("SERVER existing.irc")).should be_true

      # Should send users
      messages.any?(&.starts_with?("NICK alice")).should be_true

      # Should send channel joins
      messages.any?(&.includes?("NJOIN #test")).should be_true

      # Should end with EOB
      messages.last.should eq("EOB")
    end

    it "sends user modes correctly in burst" do
      mock_server = MockLinkServer.new("new.irc")

      # Add user with modes
      Circed::Network::NetworkState.add_user("oper", "oper", "admin.host", "Operator", "hub.irc", 0)
      if user = Circed::Network::NetworkState.get_user("oper")
        user.modes << 'o' # Operator mode
        user.modes << 'i' # Invisible mode
      end

      Circed::Network::BurstProtocol.send_burst(mock_server)

      # Check NICK line includes modes
      nick_message = mock_server.sent_messages.find(&.starts_with?("NICK oper"))
      nick_message.should_not be_nil
      # Modes should be in format: +oi
      nick_message.try(&.includes?("+oi")).should be_true
    end

    it "sends away messages in burst" do
      mock_server = MockLinkServer.new("new.irc")

      # Add user with away message - need to set it directly in NetworkState
      Circed::Network::NetworkState.add_user("afk_user", "afk", "host", "AFK User", "hub.irc", 0)
      # We need to add a method to set away message, or modify the internal hash directly
      # For now, we'll use the proper AWAY processing that BurstProtocol handles
      params = ["afk_user", ":Gone fishing"]
      Circed::Network::BurstProtocol.process_burst_message("AWAY", params, mock_server)

      # Clear messages from processing
      mock_server.clear_messages

      Circed::Network::BurstProtocol.send_burst(mock_server)

      # Should send AWAY message
      away_message = mock_server.sent_messages.find(&.starts_with?("AWAY afk_user"))
      away_message.should_not be_nil
      away_message.try(&.includes?("Gone fishing")).should be_true
    end

    it "sends channel topics in burst" do
      mock_server = MockLinkServer.new("new.irc")

      # Add channel and user first
      Circed::Network::NetworkState.add_channel("#topic_chan")
      Circed::Network::NetworkState.add_user("user", "user", "host", "User", "hub.irc", 0)
      Circed::Network::NetworkState.join_user_to_channel("user", "#topic_chan")

      # Set topic using burst protocol processing
      params = ["#topic_chan", "admin", ":Welcome to the channel!"]
      Circed::Network::BurstProtocol.process_burst_message("TOPIC", params, mock_server)

      # Clear messages from processing
      mock_server.clear_messages

      Circed::Network::BurstProtocol.send_burst(mock_server)

      # Should send TOPIC message
      topic_message = mock_server.sent_messages.find(&.starts_with?("TOPIC #topic_chan"))
      topic_message.should_not be_nil
      topic_message.try(&.includes?("Welcome to the channel!")).should be_true
    end

    it "groups users by modes in NJOIN efficiently" do
      mock_server = MockLinkServer.new("new.irc")

      # Add channel with users having different modes
      Circed::Network::NetworkState.add_channel("#modes")

      # Add ops
      ["op1", "op2"].each do |nick|
        Circed::Network::NetworkState.add_user(nick, nick, "host", nick, "hub.irc", 0)
        Circed::Network::NetworkState.join_user_to_channel(nick, "#modes", Set{'o'})
      end

      # Add voices
      ["voice1", "voice2"].each do |nick|
        Circed::Network::NetworkState.add_user(nick, nick, "host", nick, "hub.irc", 0)
        Circed::Network::NetworkState.join_user_to_channel(nick, "#modes", Set{'v'})
      end

      # Add regular users
      ["user1", "user2"].each do |nick|
        Circed::Network::NetworkState.add_user(nick, nick, "host", nick, "hub.irc", 0)
        Circed::Network::NetworkState.join_user_to_channel(nick, "#modes")
      end

      Circed::Network::BurstProtocol.send_burst(mock_server)

      # Should send separate NJOIN for each mode group
      njoin_messages = mock_server.sent_messages.select(&.includes?("NJOIN #modes"))

      # Should have messages for ops, voices, and regular users
      njoin_messages.size.should be >= 1
      njoin_messages.any?(&.includes?("+o")).should be_true
      njoin_messages.any?(&.includes?("+v")).should be_true
    end

    it "excludes target server's own users from burst" do
      mock_server = MockLinkServer.new("target.irc")

      # Add users on different servers
      Circed::Network::NetworkState.add_user("local_user", "local", "host", "Local", "hub.irc", 0)
      Circed::Network::NetworkState.add_user("target_user", "target", "host", "Target", "target.irc", 0)

      # Both in same channel
      Circed::Network::NetworkState.add_channel("#shared")
      Circed::Network::NetworkState.join_user_to_channel("local_user", "#shared")
      Circed::Network::NetworkState.join_user_to_channel("target_user", "#shared")

      Circed::Network::BurstProtocol.send_burst(mock_server)

      # Should send local_user but not target_user
      nick_messages = mock_server.sent_messages.select(&.starts_with?("NICK "))
      nick_messages.any?(&.includes?("local_user")).should be_true
      nick_messages.any?(&.includes?("target_user")).should be_false

      # NJOIN should only include local_user
      njoin_messages = mock_server.sent_messages.select(&.includes?("NJOIN"))
      njoin_messages.any?(&.includes?("local_user")).should be_true
      njoin_messages.any?(&.includes?("target_user")).should be_false
    end

    it "handles empty channels correctly" do
      mock_server = MockLinkServer.new("new.irc")

      # Add empty channel (shouldn't be sent)
      Circed::Network::NetworkState.add_channel("#empty")

      # Add channel with users
      Circed::Network::NetworkState.add_user("user", "user", "host", "User", "hub.irc", 0)
      Circed::Network::NetworkState.add_channel("#populated")
      Circed::Network::NetworkState.join_user_to_channel("user", "#populated")

      Circed::Network::BurstProtocol.send_burst(mock_server)

      # Should not send empty channel
      njoin_messages = mock_server.sent_messages.select(&.includes?("NJOIN"))
      njoin_messages.any?(&.includes?("#empty")).should be_false
      njoin_messages.any?(&.includes?("#populated")).should be_true
    end
  end

  describe "burst message processing" do
    it "processes received SERVER messages" do
      mock_server = MockLinkServer.new("sender.irc")

      # Process SERVER message
      params = ["remote.irc", "2", "301", ":Remote IRC Server"]
      Circed::Network::BurstProtocol.process_burst_message("SERVER", params, mock_server)

      # Server should be added
      server = Circed::Network::NetworkState.get_server("remote.irc")
      server.should_not be_nil
      server.try(&.hopcount).should eq(2)
      server.try(&.description).should eq("Remote IRC Server")
      server.try(&.token).should eq("301")
    end

    it "processes received NICK messages" do
      mock_server = MockLinkServer.new("sender.irc")

      # Process NICK message
      params = ["alice", "1", "alice", "alice.host", "301", "+io", ":Alice User"]
      Circed::Network::BurstProtocol.process_burst_message("NICK", params, mock_server)

      # User should be added
      user = Circed::Network::NetworkState.get_user("alice")
      user.should_not be_nil
      user.try(&.username).should eq("alice")
      user.try(&.hostname).should eq("alice.host")
      user.try(&.realname).should eq("Alice User")
      user.try(&.modes.includes?('i')).should be_true
      user.try(&.modes.includes?('o')).should be_true
    end

    it "processes received NJOIN messages" do
      mock_server = MockLinkServer.new("sender.irc")

      # Add users first
      ["alice", "bob", "charlie"].each do |nick|
        Circed::Network::NetworkState.add_user(nick, nick, "host", nick, "remote.irc", 1)
      end

      # Process NJOIN message
      params = ["#test", "+ov", ":alice bob charlie"]
      Circed::Network::BurstProtocol.process_burst_message("NJOIN", params, mock_server)

      # Channel should exist with users
      channel = Circed::Network::NetworkState.get_channel("#test")
      channel.should_not be_nil
      channel.try(&.members.size).should eq(3)

      # Check user modes in channel
      alice_modes = channel.try(&.members["alice"]?)
      alice_modes.should_not be_nil
      alice_modes.try(&.includes?('o')).should be_true
      alice_modes.try(&.includes?('v')).should be_true
    end

    it "processes EOB (End of Burst)" do
      mock_server = MockLinkServer.new("sender.irc")

      # Process EOB - should not crash
      Circed::Network::BurstProtocol.process_burst_message("EOB", [] of String, mock_server)
    end
  end
end
