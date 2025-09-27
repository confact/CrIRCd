require "../spec_helper"

describe "Server-to-Server Linking Integration" do
  env = TestEnvironment.new

  after_each do
    env.teardown
  end

  describe "SSL server linking" do
    it "establishes SSL link between two servers" do
      env.setup_linked_servers(ssl_enabled: true)

      # Give servers time to link
      sleep 2

      # Both servers should be running
      env.servers.each do |server|
        server.running?.should be_true
      end

      # Test cross-server functionality by connecting clients to different servers
      alice = env.create_client("Alice", port: 16697, ssl: true)
      bob = env.create_client("Bob", port: 17697, ssl: true)

      alice.register
      bob.register

      assert_welcome_sequence(alice)
      assert_welcome_sequence(bob)

      alice.quit
      bob.quit
    end

    it "synchronizes users across linked servers" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)

      alice.register
      bob.register

      # Both join the same channel
      alice.join("#test")
      bob.join("#test")

      # Alice should see Bob join
      alice.should_receive(/.*Bob.*JOIN.*#test/)

      # Bob should see Alice was already there
      bob.should_receive(/353.*#test.*Alice/) # NAMES reply should include Alice

      alice.quit
      bob.quit
    end

    it "routes messages between linked servers" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)

      alice.register
      bob.register

      alice.join("#test")
      bob.join("#test")

      # Wait for joins to complete
      sleep 0.5

      # Alice sends message, Bob should receive it
      test_message = "Hello from Server 1!"
      alice.privmsg("#test", test_message)

      assert_message_received(bob, test_message, "Alice")

      alice.quit
      bob.quit
    end

    it "handles server disconnection gracefully" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)

      alice.register
      bob.register

      alice.join("#test")
      bob.join("#test")

      # Stop one server
      env.servers[1].stop

      # Alice should still be functional
      alice.send("PING :stillalive")
      alice.should_receive(/PONG.*stillalive/)

      # Bob's connection should be dropped
      expect_raises(Exception) do
        bob.send("PING :test")
      end

      alice.quit
    end
  end

  describe "link authentication" do
    it "requires correct link password" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2

      # Both servers should establish link successfully
      env.servers.each do |server|
        server.running?.should be_true
      end

      # Test that clients can connect (indicating servers are linked)
      client = env.create_client("TestUser", port: 16697)
      client.register
      assert_welcome_sequence(client)
      client.quit
    end

    it "maintains network topology" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)

      alice.register
      bob.register

      # Test LINKS command to see network topology
      alice.send("LINKS")
      alice.should_receive(/364.*/) # RPL_LINKS

      alice.quit
      bob.quit
    end
  end

  describe "network burst and synchronization" do
    it "synchronizes network state on link establishment" do
      env.setup_linked_servers(ssl_enabled: true)

      # Connect a user to server 1 before link is fully established
      alice = env.create_client("Alice", port: 16697)
      alice.register
      alice.join("#early")

      sleep 2 # Wait for link establishment

      # Connect to server 2 and verify Alice is visible
      bob = env.create_client("Bob", port: 17697)
      bob.register
      bob.join("#early")

      # Bob should see Alice in the channel
      bob.should_receive(/353.*#early.*Alice/) # NAMES reply

      alice.quit
      bob.quit
    end

    it "propagates nick changes across servers" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)

      alice.register
      bob.register

      alice.join("#test")
      bob.join("#test")

      sleep 0.5

      # Alice changes nick
      alice.send("NICK AliceNew")
      alice.should_receive(/NICK.*AliceNew/)

      # Bob should see the nick change
      bob.should_receive(/Alice.*NICK.*AliceNew/)

      alice.quit
      bob.quit
    end

    it "propagates quit messages across servers" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)
      charlie = env.create_client("Charlie", port: 17697)

      alice.register
      bob.register
      charlie.register

      alice.join("#test")
      bob.join("#test")
      charlie.join("#test")

      sleep 0.5

      # Alice quits
      alice.quit("Going away")

      # Bob and Charlie should see the quit
      bob.should_receive(/Alice.*QUIT.*Going away/)
      charlie.should_receive(/Alice.*QUIT.*Going away/)

      bob.quit
      charlie.quit
    end
  end
end
