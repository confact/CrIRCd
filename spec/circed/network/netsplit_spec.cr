require "../../spec_helper"

describe Circed::Network::NetworkState do
  before_each do
    clear_repositories
  end

  after_each do
    clear_repositories
  end

  describe "netsplit handling" do
    it "handles simple server disconnection" do
      # Set up network: Hub ← Server1
      Circed::Network::NetworkState.add_server("server1.irc", 1, "Server 1", nil, "101")
      Circed::Network::NetworkState.add_server_link("localhost", "server1.irc")

      # Add user on server1
      Circed::Network::NetworkState.add_user("alice", "alice", "server1.irc", "Alice", "server1.irc", 1)

      # Add channel with user
      Circed::Network::NetworkState.add_channel("#test")
      Circed::Network::NetworkState.join_user_to_channel("alice", "#test")
      channel_repository.add_member("#test", "alice")

      # Verify initial state
      Circed::Network::NetworkState.stats[:servers].should eq(1)
      Circed::Network::NetworkState.stats[:users].should eq(1)
      Circed::Network::NetworkState.get_channel("#test").try(&.members.size).should eq(1)

      # Disconnect server1
      Circed::Network::NetworkState.remove_server("server1.irc")

      # Verify cleanup
      Circed::Network::NetworkState.stats[:servers].should eq(0)
      Circed::Network::NetworkState.stats[:users].should eq(0)
      Circed::Network::NetworkState.get_channel("#test").should be_nil
      channel_repository["#test"]?.should be_nil
    end

    it "handles transitive server disconnection" do
      # Set up network: Hub ← Server1 ← Server2
      Circed::Network::NetworkState.add_server("server1.irc", 1, "Server 1", nil, "101")
      Circed::Network::NetworkState.add_server("server2.irc", 2, "Server 2", nil, "102")
      Circed::Network::NetworkState.add_server_link("localhost", "server1.irc")
      Circed::Network::NetworkState.add_server_link("server1.irc", "server2.irc")

      # Add users on both servers
      Circed::Network::NetworkState.add_user("alice", "alice", "server1.irc", "Alice", "server1.irc", 1)
      Circed::Network::NetworkState.add_user("bob", "bob", "server2.irc", "Bob", "server2.irc", 2)

      # Initial state: 2 servers, 2 users
      Circed::Network::NetworkState.stats[:servers].should eq(2)
      Circed::Network::NetworkState.stats[:users].should eq(2)

      # Disconnect server1 (should also disconnect server2)
      Circed::Network::NetworkState.remove_server("server1.irc")

      # Both servers and users should be gone
      Circed::Network::NetworkState.stats[:servers].should eq(0)
      Circed::Network::NetworkState.stats[:users].should eq(0)
      Circed::Network::NetworkState.get_user("alice").should be_nil
      Circed::Network::NetworkState.get_user("bob").should be_nil
    end

    it "preserves unaffected servers during netsplit" do
      # Set up network: Hub ← Server1 ← Server2, Hub ← Server3
      Circed::Network::NetworkState.add_server("server1.irc", 1, "Server 1", nil, "101")
      Circed::Network::NetworkState.add_server("server2.irc", 2, "Server 2", nil, "102")
      Circed::Network::NetworkState.add_server("server3.irc", 1, "Server 3", nil, "103")

      Circed::Network::NetworkState.add_server_link("localhost", "server1.irc")
      Circed::Network::NetworkState.add_server_link("server1.irc", "server2.irc")
      Circed::Network::NetworkState.add_server_link("localhost", "server3.irc")

      # Add users on all servers
      Circed::Network::NetworkState.add_user("alice", "alice", "server1.irc", "Alice", "server1.irc", 1)
      Circed::Network::NetworkState.add_user("bob", "bob", "server2.irc", "Bob", "server2.irc", 2)
      Circed::Network::NetworkState.add_user("charlie", "charlie", "server3.irc", "Charlie", "server3.irc", 1)

      # Add channel with users from all servers
      Circed::Network::NetworkState.add_channel("#test")
      Circed::Network::NetworkState.join_user_to_channel("alice", "#test")
      Circed::Network::NetworkState.join_user_to_channel("bob", "#test")
      Circed::Network::NetworkState.join_user_to_channel("charlie", "#test")

      # Initial state: 3 servers, 3 users, 3 users in channel
      Circed::Network::NetworkState.stats[:servers].should eq(3)
      Circed::Network::NetworkState.stats[:users].should eq(3)
      Circed::Network::NetworkState.get_channel("#test").try(&.members.size).should eq(3)

      # Disconnect server1 (should disconnect server1 and server2, but preserve server3)
      Circed::Network::NetworkState.remove_server("server1.irc")

      # Only server3 and charlie should remain
      Circed::Network::NetworkState.stats[:servers].should eq(1)
      Circed::Network::NetworkState.stats[:users].should eq(1)
      Circed::Network::NetworkState.get_user("charlie").should_not be_nil
      Circed::Network::NetworkState.get_user("alice").should be_nil
      Circed::Network::NetworkState.get_user("bob").should be_nil

      # Channel should only have charlie
      channel = Circed::Network::NetworkState.get_channel("#test")
      channel.should_not be_nil
      channel.try(&.members.size).should eq(1)
      channel.try(&.members.has_key?("charlie")).should be_true
    end

    it "removes empty channels after netsplit" do
      # Set up network with users only on server1
      Circed::Network::NetworkState.add_server("server1.irc", 1, "Server 1", nil, "101")
      Circed::Network::NetworkState.add_server_link("localhost", "server1.irc")

      # Add users only on server1
      Circed::Network::NetworkState.add_user("alice", "alice", "server1.irc", "Alice", "server1.irc", 1)
      Circed::Network::NetworkState.add_user("bob", "bob", "server1.irc", "Bob", "server1.irc", 1)

      # Add channel with only users from server1
      Circed::Network::NetworkState.add_channel("#empty_after_split")
      Circed::Network::NetworkState.join_user_to_channel("alice", "#empty_after_split")
      Circed::Network::NetworkState.join_user_to_channel("bob", "#empty_after_split")

      # Verify channel exists
      Circed::Network::NetworkState.get_channel("#empty_after_split").should_not be_nil

      # Disconnect server1
      Circed::Network::NetworkState.remove_server("server1.irc")

      # Channel should be removed since it became empty
      Circed::Network::NetworkState.get_channel("#empty_after_split").should be_nil
      Circed::Network::NetworkState.stats[:channels].should eq(0)
    end

    it "handles complex network topology splits" do
      # Set up more complex network: Hub ← A ← B ← C, Hub ← D ← E
      %w[A B C D E].each_with_index do |name, i|
        Circed::Network::NetworkState.add_server("#{name}.irc", i + 1, "Server #{name}", nil, "10#{i}")
      end

      # Build topology
      Circed::Network::NetworkState.add_server_link("localhost", "A.irc")
      Circed::Network::NetworkState.add_server_link("A.irc", "B.irc")
      Circed::Network::NetworkState.add_server_link("B.irc", "C.irc")
      Circed::Network::NetworkState.add_server_link("localhost", "D.irc")
      Circed::Network::NetworkState.add_server_link("D.irc", "E.irc")

      # Add users
      %w[A B C D E].each do |name|
        Circed::Network::NetworkState.add_user("user#{name}", "user#{name}", "#{name}.irc", "User #{name}", "#{name}.irc", 1)
      end

      # Initial: 5 servers, 5 users
      Circed::Network::NetworkState.stats[:servers].should eq(5)
      Circed::Network::NetworkState.stats[:users].should eq(5)

      # Disconnect B (should take down C but preserve A, D, E)
      Circed::Network::NetworkState.remove_server("B.irc")

      # Should have A, D, E remaining (3 servers, 3 users)
      Circed::Network::NetworkState.stats[:servers].should eq(3)
      Circed::Network::NetworkState.stats[:users].should eq(3)
      Circed::Network::NetworkState.get_user("userA").should_not be_nil
      Circed::Network::NetworkState.get_user("userD").should_not be_nil
      Circed::Network::NetworkState.get_user("userE").should_not be_nil
      Circed::Network::NetworkState.get_user("userB").should be_nil
      Circed::Network::NetworkState.get_user("userC").should be_nil
    end
  end

  describe "network topology management" do
    it "streams servers matching a mask" do
      Circed::Network::NetworkState.add_server("one.irc", 1, "One")
      Circed::Network::NetworkState.add_server("two.test", 1, "Two")

      names = Circed::Network::NetworkState.server_list("*.irc").map(&.name).to_a
      names.should eq(["one.irc"])
    end

    it "finds the first hop on the shortest route" do
      Circed::Network::NetworkState.add_server_link("localhost", "one.irc")
      Circed::Network::NetworkState.add_server_link("one.irc", "two.irc")
      Circed::Network::NetworkState.add_server_link("two.irc", "target.irc")

      Circed::Network::NetworkState.route_to_server("target.irc", "localhost").should eq("one.irc")
    end

    it "rejects cyclic server links" do
      Circed::Network::NetworkState.add_server_link("localhost", "one.irc").should be_true
      Circed::Network::NetworkState.add_server_link("one.irc", "two.irc").should be_true

      Circed::Network::NetworkState.add_server_link("two.irc", "localhost").should be_false
      Circed::Network::NetworkState.topology["two.irc"].includes?("localhost").should be_false
    end

    it "rejects duplicate server routes without replacing server state" do
      Circed::Network::NetworkState.add_server("one.irc", 1, "Original").should be_true

      Circed::Network::NetworkState.add_server("one.irc", 2, "Duplicate").should be_false
      Circed::Network::NetworkState.get_server("one.irc").try(&.description).should eq("Original")
    end

    it "correctly identifies disconnected servers" do
      # This tests the private method indirectly through remove_server
      Circed::Network::NetworkState.add_server("intermediate.irc", 1, "Intermediate", nil, "201")
      Circed::Network::NetworkState.add_server("leaf1.irc", 2, "Leaf 1", nil, "202")
      Circed::Network::NetworkState.add_server("leaf2.irc", 2, "Leaf 2", nil, "203")

      Circed::Network::NetworkState.add_server_link("localhost", "intermediate.irc")
      Circed::Network::NetworkState.add_server_link("intermediate.irc", "leaf1.irc")
      Circed::Network::NetworkState.add_server_link("intermediate.irc", "leaf2.irc")

      # Disconnect intermediate should take down both leaves
      Circed::Network::NetworkState.remove_server("intermediate.irc")

      Circed::Network::NetworkState.stats[:servers].should eq(0)
      Circed::Network::NetworkState.get_server("leaf1.irc").should be_nil
      Circed::Network::NetworkState.get_server("leaf2.irc").should be_nil
    end
  end
end
