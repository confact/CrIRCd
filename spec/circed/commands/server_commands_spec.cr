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
    clear_repositories
    Circed::Network::NetworkState.clear_all_state
    Circed::Network::LineState.clear
    Circed::ServerHandler.servers.clear
  end

  after_each do
    clear_repositories
    Circed::Network::LineState.clear
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

    it "does not forward an already processed SQUIT" do
      source = RecordingLinkServer.new("source.irc")
      peer = RecordingLinkServer.new("peer.irc")
      Circed::ServerHandler.add_server(source)
      Circed::ServerHandler.add_server(peer)
      Circed::Network::NetworkState.add_server("target.irc", 1, "Target")

      2.times do
        Circed::Commands::ServerCommands.squit(source, ["target.irc", ":Split"])
      end

      peer.sent_messages.count(&.starts_with?("SQUIT target.irc")).should eq(1)
    end

    it "does not rebroadcast SQUIT while closing its direct link" do
      source = RecordingLinkServer.new("source.irc")
      peer = RecordingLinkServer.new("peer.irc")
      Circed::ServerHandler.add_server(source)
      Circed::ServerHandler.add_server(peer)
      Circed::Network::NetworkState.add_server("source.irc", 1, "Source")

      Circed::Commands::ServerCommands.squit(source, ["source.irc", ":Split"])

      peer.sent_messages.count(&.starts_with?("SQUIT source.irc")).should eq(1)
      source.sent_messages.should contain("CLOSE Received SQUIT: Split")
      Circed::ServerHandler.servers.includes?(source).should be_false
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

  describe "WALLOPS command" do
    it "preserves a multiword trailing parameter when forwarding" do
      source = RecordingLinkServer.new("source.irc")
      peer = RecordingLinkServer.new("peer.irc")
      Circed::ServerHandler.add_server(source)
      Circed::ServerHandler.add_server(peer)

      Circed::Commands::ServerCommands.wallops(source, ["Network maintenance"])

      peer.sent_messages.should contain("WALLOPS :Network maintenance\r\n")
    end

    it "forwards server wallops to local users with +w mode" do
      link_server = create_link_server
      wallops_user = create_test_client("Alice")
      quiet_user = create_test_client("Bob")
      user_repository["Alice"]?.try { |user| user.modes << 'w' }

      Circed::Commands::ServerCommands.wallops(link_server, [":Network maintenance"])

      wallops_user.socket.as(DummySocket).sent_data.join.should contain("WALLOPS :Network maintenance")
      quiet_user.socket.as(DummySocket).sent_data.join.should_not contain("WALLOPS")
    end

    it "handles empty WALLOPS parameters gracefully" do
      link_server = create_link_server

      Circed::Commands::ServerCommands.wallops(link_server, [] of String)
    end
  end

  describe "GLINE command" do
    it "stores and enforces remote G-lines" do
      link_server = create_link_server
      victim = create_test_client("Bob")
      if user = user_repository["Bob"]?
        user.hostname = "bad.example"
      end

      Circed::Commands::ServerCommands.gline(link_server, ["*@bad.example", "0", "remote.oper", ":Spam"])

      user_repository["Bob"]?.should be_nil
      victim.socket.as(DummySocket).sent_data.join.should contain("ERROR :GLINE: Spam")
    end

    it "removes remote G-lines by mask" do
      link_server = create_link_server

      Circed::Commands::ServerCommands.gline(link_server, ["*@bad.example", "0", "remote.oper", ":Spam"])
      Circed::Commands::ServerCommands.gline(link_server, ["*@bad.example"])

      context = Circed::Domain::BanMatchContext.new(
        "Bob",
        "bob",
        "bad.example",
        "192.0.2.10",
        "Bob",
        "Bob!bob@bad.example",
        [] of String
      )
      Circed::Network::LineState.matching(context).should be_nil
    end

    it "does not forward duplicate G-lines" do
      link_server = create_link_server
      peer = RecordingLinkServer.new("peer.irc")
      Circed::ServerHandler.add_server(link_server)
      Circed::ServerHandler.add_server(peer)

      Circed::Commands::ServerCommands.gline(link_server, ["*@bad.example", "0", "remote.oper", ":Spam"])
      Circed::Commands::ServerCommands.gline(link_server, ["*@bad.example", "0", "remote.oper", ":Spam"])

      peer.sent_messages.count(&.starts_with?("GLINE *!*@bad.example")).should eq(1)
    end
  end

  describe "NJOIN command" do
    it "joins multiple users to channel efficiently" do
      link_server = create_link_server
      # Set up users
      Circed::Network::NetworkState.add_user("alice", "alice", "server.irc", "Alice", link_server.name, 1)
      Circed::Network::NetworkState.add_user("bob", "bob", "server.irc", "Bob", link_server.name, 1)

      # Send NJOIN
      Circed::Commands::ServerCommands.njoin(link_server, ["#test", "100", "+", "+o", ":alice bob"])

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

    it "does not merge trailing nicknames in larger NJOIN messages" do
      link_server = create_link_server
      nicknames = (1..101).map { |index| "u#{index}" }

      nicknames.each do |nickname|
        Circed::Network::NetworkState.add_user(nickname, nickname, "host", nickname, link_server.name)
      end
      Circed::Commands::ServerCommands.njoin(link_server, ["#large", "100", "+", "+", ":#{nicknames.join(' ')}"])

      channel = Circed::Network::NetworkState.get_channel("#large")
      channel.should_not be_nil
      channel.try(&.members.size).should eq(101)
      channel.try(&.members.has_key?("u100 u101")).should be_false
      channel.try(&.members.has_key?("u101")).should be_true
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
