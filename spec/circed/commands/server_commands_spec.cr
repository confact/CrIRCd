require "../../spec_helper"

def create_link_server
  socket = DummySocket.new
  socket.add_receive_data("PASS testpass")
  socket.add_receive_data("SERVER test.server 1 :Test Server")
  remote_addr = Socket::IPAddress.new("127.0.0.1", 12345)
  Circed::LinkServer.new(socket.as(Circed::Network::SSLSocket::IRCSocket), ["PASS testpass", "SERVER test.server 1 :Test Server"], remote_addr)
end

describe Circed::Commands::ServerCommands do
  before_each do
    Circed::Network::NetworkState.clear_all_state
  end

  describe "SQUIT command" do
    it "handles server quit message" do
      link_server = create_link_server
      # Set up network state
      Circed::Network::NetworkState.add_server("target.irc", 1, "Target Server", nil, "301")
      Circed::Network::NetworkState.add_user("testuser", "test", "target.irc", "Test User", "target.irc", 1)

      # Initial state
      Circed::Network::NetworkState.stats[:servers].should eq(1)
      Circed::Network::NetworkState.stats[:users].should eq(1)

      # Send SQUIT
      Circed::Commands::ServerCommands.squit(link_server, ["target.irc", ":Server maintenance"])

      # Server and user should be removed
      Circed::Network::NetworkState.stats[:servers].should eq(0)
      Circed::Network::NetworkState.stats[:users].should eq(0)
      Circed::Network::NetworkState.get_server("target.irc").should be_nil
      Circed::Network::NetworkState.get_user("testuser").should be_nil
    end

    it "handles SQUIT with transitive disconnections" do
      link_server = create_link_server
      # Set up chain: Hub ← server1 ← server2
      Circed::Network::NetworkState.add_server("server1.irc", 1, "Server 1", nil, "401")
      Circed::Network::NetworkState.add_server("server2.irc", 2, "Server 2", nil, "402")
      Circed::Network::NetworkState.add_server_link("localhost", "server1.irc")
      Circed::Network::NetworkState.add_server_link("server1.irc", "server2.irc")

      # Add users
      Circed::Network::NetworkState.add_user("alice", "alice", "server1.irc", "Alice", "server1.irc", 1)
      Circed::Network::NetworkState.add_user("bob", "bob", "server2.irc", "Bob", "server2.irc", 2)

      # SQUIT server1 should remove both servers
      Circed::Commands::ServerCommands.squit(link_server, ["server1.irc", ":Network maintenance"])

      Circed::Network::NetworkState.stats[:servers].should eq(0)
      Circed::Network::NetworkState.stats[:users].should eq(0)
    end

    it "handles empty SQUIT parameters gracefully" do
      link_server = create_link_server
      # Should not crash with empty parameters
      Circed::Commands::ServerCommands.squit(link_server, [] of String)

      # Network state should be unchanged
      Circed::Network::NetworkState.stats[:servers].should eq(0)
    end
  end

  describe "KILL command" do
    it "removes user from network" do
      link_server = create_link_server
      # Set up user
      Circed::Network::NetworkState.add_user("victim", "victim", "server.irc", "Victim User", "server.irc", 1)
      Circed::Network::NetworkState.add_channel("#test")
      Circed::Network::NetworkState.join_user_to_channel("victim", "#test")

      # Initial state
      Circed::Network::NetworkState.get_user("victim").should_not be_nil
      Circed::Network::NetworkState.get_channel("#test").try(&.members.has_key?("victim")).should be_true

      # Send KILL
      Circed::Commands::ServerCommands.kill(link_server, ["victim", ":Spam"])

      # User should be removed
      Circed::Network::NetworkState.get_user("victim").should be_nil
      Circed::Network::NetworkState.get_channel("#test").try(&.members.has_key?("victim")).should be_false
    end

    it "handles KILL with insufficient parameters" do
      link_server = create_link_server
      # Should not crash with insufficient parameters
      Circed::Commands::ServerCommands.kill(link_server, ["victim"])
      Circed::Commands::ServerCommands.kill(link_server, [] of String)
    end
  end

  describe "NJOIN command" do
    it "joins multiple users to channel efficiently" do
      link_server = create_link_server
      # Set up users
      Circed::Network::NetworkState.add_user("alice", "alice", "server.irc", "Alice", "server.irc", 1)
      Circed::Network::NetworkState.add_user("bob", "bob", "server.irc", "Bob", "server.irc", 1)

      # Send NJOIN
      Circed::Commands::ServerCommands.njoin(link_server, ["#test", "+o", ":alice bob"])

      # Channel should exist with both users
      channel = Circed::Network::NetworkState.get_channel("#test")
      channel.should_not be_nil
      channel.try(&.members.size).should eq(2)
      channel.try(&.members.has_key?("alice")).should be_true
      channel.try(&.members.has_key?("bob")).should be_true

      # Users should have +o mode
      alice_modes = channel.try(&.members["alice"]?)
      alice_modes.should_not be_nil
      alice_modes.try(&.includes?('o')).should be_true
    end

    it "handles NJOIN with insufficient parameters" do
      link_server = create_link_server
      # Should not crash
      Circed::Commands::ServerCommands.njoin(link_server, ["#test"])
      Circed::Commands::ServerCommands.njoin(link_server, [] of String)
    end
  end

  describe "INFO commands" do
    describe "basic command execution" do
      it "executes without crashing" do
        client = Circed::Client.new(DummySocket.new.as(Circed::Network::SSLSocket::IRCSocket), [] of String)
        client.nickname = "testuser"

        # Test all commands don't crash
        Circed::Commands::ServerCommands.links(client, ["*"])
        Circed::Commands::ServerCommands.stats(client, ["u"])
        Circed::Commands::ServerCommands.time(client, [] of String)
        Circed::Commands::ServerCommands.version(client, [] of String)
        Circed::Commands::ServerCommands.admin(client, [] of String)
      end
    end
  end
end
