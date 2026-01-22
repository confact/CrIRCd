#!/usr/bin/env crystal

# Integration test for CrIRCd server functionality
# This test verifies both client and server-to-server communication work correctly

require "spec"
require "./src/circed"

include Circed

describe "CrIRCd Integration Test" do
  before_each do
    # Clear all repositories and network state
    Infrastructure::ServiceLocator.user_repository.clear
    Infrastructure::ServiceLocator.channel_repository.clear
    Network::NetworkState.clear_all_state
  end

  describe "Client Functionality" do
    it "handles complete user lifecycle correctly" do
      # Create test client
      socket = DummySocket.new
      buffer = ["NICK testuser", "USER test test localhost :Test User"]
      client = Client.new(socket, buffer)

      # Process authentication
      client.nickname = "testuser"
      client.user = ["test", "0", "localhost", ":Test User"]

      # Verify user is registered
      user_repository = Infrastructure::ServiceLocator.user_repository
      user_repository.has_client?("testuser").should be_true

      # Test JOIN
      Actions::Join.call(client, "#testchan")

      # Verify channel operations
      channel_repository = Infrastructure::ServiceLocator.channel_repository
      channel = channel_repository.get("#testchan")
      channel.should_not be_nil
      if ch = channel
        ch.has_member?("testuser").should be_true
      end

      # Test PRIVMSG
      socket2 = DummySocket.new
      buffer2 = ["NICK user2", "USER test2 test2 localhost :Test User 2"]
      client2 = Client.new(socket2, buffer2)
      client2.nickname = "user2"
      client2.user = ["test2", "0", "localhost", ":Test User 2"]
      user_repository.add_client(client2)

      Actions::Join.call(client2, "#testchan")
      Actions::Privmsg.call(client, "#testchan", ["#testchan", "Hello", "World"])

      # Test PART
      Actions::Part.call(client, "#testchan")
      channel = channel_repository.get("#testchan")
      if ch = channel
        ch.has_member?("testuser").should be_false
      end

      # Test QUIT
      Actions::Quit.call(client, "Goodbye")
      user_repository.has_client?("testuser").should be_false
    end

    it "handles network state synchronization" do
      # Create test client
      socket = DummySocket.new
      buffer = ["NICK netuser", "USER net net localhost :Net User"]
      client = Client.new(socket, buffer)

      client.nickname = "netuser"
      client.user = ["net", "0", "localhost", ":Net User"]

      # Test network state sync
      if user = client.user
        Network::NetworkState.add_user(
          "netuser",
          user.name,
          client.host || "localhost",
          user.realname,
          Server.name
        )
      end

      # Verify user exists in network state
      network_user = Network::NetworkState.get_user("netuser")
      network_user.should_not be_nil
      if user = network_user
        user.nickname.should eq("netuser")
      end

      # Test channel operations with network state
      Network::NetworkState.add_channel("#netchan")
      Network::NetworkState.join_user_to_channel("netuser", "#netchan")

      network_channel = Network::NetworkState.get_channel("#netchan")
      network_channel.should_not be_nil
      if channel = network_channel
        channel.members.has_key?("netuser").should be_true
      end
    end
  end

  describe "Server-to-Server Communication" do
    it "handles server connections and message routing" do
      # Create mock link server
      buffer = ["PASS testpass", "SERVER test.server 1 :Test Server"]

      # Test server authentication
      commands = Server.extract_commands(buffer)
      commands.should contain("PASS")
      commands.should contain("SERVER")

      connection_type = Server.detect_connection_type(buffer)
      connection_type.should eq(:server)

      # Test network state with multiple servers
      Network::NetworkState.add_server("server1", 1, "Test Server 1")
      Network::NetworkState.add_server("server2", 2, "Test Server 2")

      servers = Network::NetworkState.servers
      servers.size.should eq(2)
      servers.has_key?("server1").should be_true
      servers.has_key?("server2").should be_true
    end

    it "handles server commands correctly" do
      # Test SQUIT handling

      # Add test servers to network state
      Network::NetworkState.add_server("test.server", 1, "Test Server")
      Network::NetworkState.add_user("testuser", "test", "host", "Test", "test.server")

      # Verify server and user exist
      Network::NetworkState.get_server("test.server").should_not be_nil
      Network::NetworkState.get_user("testuser").should_not be_nil

      # Simulate server quit
      Network::NetworkState.remove_server("test.server")

      # Verify cleanup
      Network::NetworkState.get_server("test.server").should be_nil
      Network::NetworkState.get_user("testuser").should be_nil
    end
  end

  describe "IRC Protocol Compliance" do
    it "validates IRC message formats" do
      # Test message parsing
      test_line = ":nick!user@host PRIVMSG #channel :Hello world"
      message = FastIRC.parse_line(test_line)

      message.command.should eq("PRIVMSG")
      message.params.should eq(["#channel", "Hello world"])
      message.prefix.should_not be_nil
      if prefix = message.prefix
        prefix.source.should eq("nick")
      end
    end

    it "handles RFC-compliant numerics" do
      # Test that numeric constants are defined
      Numerics::RPL_WELCOME.should eq("001")
      Numerics::RPL_YOURHOST.should eq("002")
      Numerics::ERR_NICKNAMEINUSE.should eq("433")
      Numerics::ERR_NOSUCHCHANNEL.should eq("403")
    end
  end

  describe "Error Handling and Edge Cases" do
    it "handles malformed commands gracefully" do
      # Test empty commands
      buffer = ["", "   ", "INVALID"]
      commands = Server.extract_commands(buffer)
      commands.should contain("INVALID")

      # Test connection type detection with malformed data
      connection_type = Server.detect_connection_type(buffer)
      connection_type.should be_nil
    end

    it "handles network splits correctly" do
      # Setup network topology
      Network::NetworkState.add_server("hub", 0, "Hub Server")
      Network::NetworkState.add_server("leaf1", 1, "Leaf Server 1")
      Network::NetworkState.add_server("leaf2", 1, "Leaf Server 2")

      Network::NetworkState.add_server_link("hub", "leaf1")
      Network::NetworkState.add_server_link("hub", "leaf2")

      # Add users on different servers
      Network::NetworkState.add_user("user1", "u1", "host1", "User 1", "leaf1")
      Network::NetworkState.add_user("user2", "u2", "host2", "User 2", "leaf2")

      # Simulate netsplit
      Network::NetworkState.remove_server("leaf1")

      # Verify affected users are removed
      Network::NetworkState.get_user("user1").should be_nil
      Network::NetworkState.get_user("user2").should_not be_nil
    end
  end
end

puts "Integration test completed - run with: crystal spec integration_test.cr"
