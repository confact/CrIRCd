require "../spec_helper"

describe "Message Routing Integration" do
  env = TestEnvironment.new

  after_each do
    env.teardown
  end

  describe "local message routing" do
    it "routes private messages to local users" do
      env.setup_single_server(ssl_enabled: true)

      alice = env.create_client("Alice")
      bob = env.create_client("Bob")

      alice.register
      bob.register

      # Direct private message
      alice.privmsg("Bob", "Hello Bob!")
      assert_message_received(bob, "Hello Bob!", "Alice")

      alice.quit
      bob.quit
    end

    it "routes channel messages to local channel members" do
      env.setup_single_server(ssl_enabled: true)

      alice = env.create_client("Alice")
      bob = env.create_client("Bob")
      charlie = env.create_client("Charlie")

      [alice, bob, charlie].each do |client|
        client.register
        client.join("#local")
      end

      # Channel message from Alice
      alice.privmsg("#local", "Message to local channel")

      # Bob and Charlie should receive it
      assert_message_received(bob, "Message to local channel", "Alice")
      assert_message_received(charlie, "Message to local channel", "Alice")

      [alice, bob, charlie].each(&.quit)
    end

    it "doesn't route to users not in channel" do
      env.setup_single_server(ssl_enabled: true)

      alice = env.create_client("Alice")
      bob = env.create_client("Bob")
      outsider = env.create_client("Outsider")

      alice.register
      bob.register
      outsider.register

      alice.join("#private")
      bob.join("#private")
      # Outsider doesn't join

      alice.privmsg("#private", "Private channel message")

      # Bob should receive it
      assert_message_received(bob, "Private channel message", "Alice")

      # Outsider should not receive it
      outsider.should_not_receive(/PRIVMSG.*Private channel message/)

      alice.quit
      bob.quit
      outsider.quit
    end
  end

  describe "cross-server message routing" do
    it "routes private messages across server links" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2.seconds

      alice = env.create_client("Alice", port: 16697) # Server 1
      bob = env.create_client("Bob", port: 17697)     # Server 2

      alice.register
      bob.register

      # Alice on server 1 messages Bob on server 2
      alice.privmsg("Bob", "Cross-server private message")
      assert_message_received(bob, "Cross-server private message", "Alice")

      alice.quit
      bob.quit
    end

    it "routes channel messages across server links" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2.seconds

      # Users on different servers
      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)
      charlie = env.create_client("Charlie", port: 16697)
      dave = env.create_client("Dave", port: 17697)

      [alice, bob, charlie, dave].each do |client|
        client.register
        client.join("#distributed")
      end

      sleep 0.5.seconds

      # Alice sends message
      alice.privmsg("#distributed", "Message across servers")

      # All others should receive it
      assert_message_received(bob, "Message across servers", "Alice")
      assert_message_received(charlie, "Message across servers", "Alice")
      assert_message_received(dave, "Message across servers", "Alice")

      [alice, bob, charlie, dave].each(&.quit)
    end

    it "doesn't create message loops" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2.seconds

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)

      alice.register
      bob.register

      alice.join("#noloop")
      bob.join("#noloop")

      sleep 0.5.seconds

      # Send message and count how many times it's received
      alice.privmsg("#noloop", "Loop test message")

      # Bob should receive it exactly once
      assert_message_received(bob, "Loop test message", "Alice")

      # Give time for any potential loops
      sleep 1.second

      # Should not receive duplicate
      bob.should_not_receive(/Loop test message/, timeout: 0.5.seconds)

      alice.quit
      bob.quit
    end
  end

  describe "notice routing" do
    it "routes NOTICE messages like PRIVMSG" do
      env.setup_single_server(ssl_enabled: true)

      alice = env.create_client("Alice")
      bob = env.create_client("Bob")

      alice.register
      bob.register

      alice.send("NOTICE Bob :This is a notice")
      bob.should_receive(/Alice.*NOTICE Bob :This is a notice/)

      alice.quit
      bob.quit
    end

    it "routes channel NOTICE across servers" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2.seconds

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)

      alice.register
      bob.register

      alice.join("#notices")
      bob.join("#notices")

      alice.send("NOTICE #notices :Cross-server notice")
      bob.should_receive(/Alice.*NOTICE #notices :Cross-server notice/)

      alice.quit
      bob.quit
    end
  end

  describe "CTCP message routing" do
    it "routes CTCP messages" do
      env.setup_single_server(ssl_enabled: true)

      alice = env.create_client("Alice")
      bob = env.create_client("Bob")

      alice.register
      bob.register

      # CTCP VERSION request
      alice.send("PRIVMSG Bob :\x01VERSION\x01")
      bob.should_receive(/Alice.*PRIVMSG Bob :.*VERSION/)

      alice.quit
      bob.quit
    end

    it "routes CTCP across servers" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2.seconds

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)

      alice.register
      bob.register

      # CTCP PING request across servers
      alice.send("PRIVMSG Bob :\x01PING 1234567890\x01")
      bob.should_receive(/Alice.*PRIVMSG Bob :.*PING 1234567890/)

      alice.quit
      bob.quit
    end
  end

  describe "server command routing" do
    it "routes NICK changes across servers" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2.seconds

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)

      alice.register
      bob.register

      alice.join("#nicks")
      bob.join("#nicks")

      # Alice changes nick
      alice.send("NICK AliceNew")
      alice.should_receive(/NICK.*AliceNew/)

      # Bob should see the change
      bob.should_receive(/Alice.*NICK.*AliceNew/)

      alice.quit
      bob.quit
    end

    it "routes QUIT messages across servers" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2.seconds

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)
      charlie = env.create_client("Charlie", port: 17697)

      alice.register
      bob.register
      charlie.register

      alice.join("#quits")
      bob.join("#quits")
      charlie.join("#quits")

      sleep 0.5.seconds

      # Alice quits
      alice.quit("Goodbye everyone!")

      # Bob and Charlie should see the quit
      bob.should_receive(/Alice.*QUIT.*Goodbye everyone!/)
      charlie.should_receive(/Alice.*QUIT.*Goodbye everyone!/)

      bob.quit
      charlie.quit
    end

    it "routes JOIN/PART across servers" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2.seconds

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)

      alice.register
      bob.register

      alice.join("#movements")

      # Bob joins same channel
      bob.join("#movements")

      # Alice should see Bob join
      alice.should_receive(/.*Bob.*JOIN.*#movements/)

      # Bob parts
      bob.send("PART #movements :See you later")
      bob.should_receive(/PART #movements :See you later/)

      # Alice should see Bob part
      alice.should_receive(/Bob.*PART #movements :See you later/)

      alice.quit
      bob.quit
    end
  end

  describe "error handling in routing" do
    it "handles messages to non-existent users" do
      env.setup_single_server(ssl_enabled: true)

      alice = env.create_client("Alice")
      alice.register

      alice.privmsg("NonExistent", "Hello ghost")
      alice.should_receive(/401.*NonExistent.*No such nick/) # ERR_NOSUCHNICK

      alice.quit
    end

    it "handles messages to non-existent channels" do
      env.setup_single_server(ssl_enabled: true)

      alice = env.create_client("Alice")
      alice.register

      alice.privmsg("#nonexistent", "Hello void")
      alice.should_receive(/404.*#nonexistent.*Cannot send to channel/) # ERR_CANNOTSENDTOCHAN

      alice.quit
    end

    it "handles routing when server link is down" do
      env.setup_linked_servers(ssl_enabled: true)
      sleep 2.seconds

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)

      alice.register
      bob.register

      # Break the link by stopping server 2
      env.servers[1].stop

      # Alice tries to message Bob (who was on the now-disconnected server)
      alice.privmsg("Bob", "Can you hear me?")
      alice.should_receive(/401.*Bob.*No such nick/) # ERR_NOSUCHNICK

      alice.quit
    end
  end

  describe "message flood protection" do
    it "handles rapid message sending" do
      env.setup_single_server(ssl_enabled: true)

      alice = env.create_client("Alice")
      bob = env.create_client("Bob")

      alice.register
      bob.register

      alice.join("#flood")
      bob.join("#flood")

      # Send many messages rapidly
      10.times do |i|
        alice.privmsg("#flood", "Rapid message #{i}")
      end

      # All messages should be delivered (basic flood control)
      10.times do |i|
        assert_message_received(bob, "Rapid message #{i}", "Alice")
      end

      alice.quit
      bob.quit
    end
  end
end
