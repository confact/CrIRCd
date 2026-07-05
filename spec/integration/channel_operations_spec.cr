require "../spec_helper"

describe "Channel Operations Integration" do
  env = TestEnvironment.new

  after_each do
    env.teardown
  end

  describe "channel lifecycle" do
    it "creates channel when first user joins" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16667, ssl: false)
      alice.register
      alice.join("#newchannel")

      # First user becomes operator
      alice.should_receive(/MODE #newchannel.*\+o Alice/)

      alice.quit
    end

    it "destroys channel when last user leaves" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16667, ssl: false)
      alice.register
      alice.join("#temp")

      alice.send("PART #temp :Leaving")
      alice.should_receive(/PART/)

      # Channel should now be destroyed (verified by server internal state)
      alice.quit
    end

    it "handles multiple users in channel" do
      env.setup_single_server(ssl_enabled: false)

      users = %w[Alice Bob Charlie Dave]
      clients = [] of IntegrationHelper::TestClient

      users.each do |name|
        client = env.create_client(name, port: 16667, ssl: false)
        client.register
        client.join("#multi")

        # Check that existing clients receive this user's JOIN notification
        clients.each do |existing_client|
          existing_client.should_receive(/.*#{name}.*JOIN.*#multi/)
        end

        clients << client
      end

      clients.each(&.quit)
    end
  end

  describe "channel messaging" do
    it "broadcasts messages to all channel members" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16667, ssl: false)
      bob = env.create_client("Bob", port: 16667, ssl: false)
      charlie = env.create_client("Charlie", port: 16667, ssl: false)

      [alice, bob, charlie].each do |client|
        client.register
        client.join("#broadcast")
      end

      # Alice sends message
      test_message = "Hello everyone in the channel!"
      alice.privmsg("#broadcast", test_message)

      # Bob and Charlie should receive it
      assert_message_received(bob, test_message, "Alice")
      assert_message_received(charlie, test_message, "Alice")

      # Alice should not receive her own message back
      alice.should_not_receive(/Alice.*PRIVMSG.*#{test_message}/, timeout: 0.1.seconds)

      [alice, bob, charlie].each(&.quit)
    end

    it "handles channel notices" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16667, ssl: false)
      bob = env.create_client("Bob", port: 16667, ssl: false)

      alice.register
      bob.register

      alice.join("#notices")
      bob.join("#notices")

      alice.send("NOTICE #notices :This is a notice")
      bob.should_receive(/Alice.*NOTICE #notices :This is a notice/)

      alice.quit
      bob.quit
    end

    it "prevents messages to channels user is not in" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16667, ssl: false)
      bob = env.create_client("Bob", port: 16667, ssl: false)

      alice.register
      bob.register

      alice.join("#private")
      # Bob doesn't join

      bob.privmsg("#private", "I shouldn't be able to send this")
      bob.should_receive(/404.*#private.*Cannot send to channel/) # ERR_CANNOTSENDTOCHAN

      alice.quit
      bob.quit
    end
  end

  describe "channel modes and permissions" do
    it "handles basic channel modes" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16667, ssl: false)
      alice.register
      alice.join("#modes")

      # Set moderated mode
      alice.send("MODE #modes +m")
      alice.should_receive(/MODE #modes.*\+m/)

      # Set topic lock
      alice.send("MODE #modes +t")
      alice.should_receive(/MODE #modes.*\+t/)

      # Remove modes
      alice.send("MODE #modes -mt")
      alice.should_receive(/MODE #modes.*-mt/)

      alice.quit
    end

    it "handles user privilege modes" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16667, ssl: false)
      bob = env.create_client("Bob", port: 16667, ssl: false)

      alice.register
      bob.register

      alice.join("#privileges")
      bob.join("#privileges")

      # Alice gives Bob voice
      alice.send("MODE #privileges +v Bob")
      alice.should_receive(/MODE #privileges.*\+v Bob/)
      bob.should_receive(/MODE #privileges.*\+v Bob/)

      # Alice gives Bob operator
      alice.send("MODE #privileges +o Bob")
      alice.should_receive(/MODE #privileges.*\+o Bob/)
      bob.should_receive(/MODE #privileges.*\+o Bob/)

      alice.quit
      bob.quit
    end

    it "enforces operator-only commands" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16667, ssl: false)
      bob = env.create_client("Bob", port: 16667, ssl: false)

      alice.register
      bob.register

      alice.join("#restricted")
      bob.join("#restricted")

      # Bob (non-op) tries to set mode
      bob.send("MODE #restricted +m")
      bob.should_receive(/482.*#restricted.*You're not channel operator/) # ERR_CHANOPRIVSNEEDED

      alice.quit
      bob.quit
    end

    it "handles invite-only mode" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16667, ssl: false)
      bob = env.create_client("Bob", port: 16667, ssl: false)

      alice.register
      bob.register

      alice.join("#invite")

      # Set invite-only
      alice.send("MODE #invite +i")
      alice.should_receive(/MODE #invite.*\+i/)

      # Bob tries to join
      bob.send("JOIN #invite")
      bob.should_receive(/473.*#invite.*Cannot join channel \(\+i\)/) # ERR_INVITEONLYCHAN

      # Alice invites Bob
      alice.send("INVITE Bob #invite")
      alice.should_receive(/341.*Bob #invite/) # RPL_INVITING

      # Now Bob can join
      bob.join("#invite")

      alice.quit
      bob.quit
    end
  end

  describe "NAMES and WHO commands" do
    it "returns channel member list with NAMES" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16667, ssl: false)
      bob = env.create_client("Bob", port: 16667, ssl: false)

      alice.register
      bob.register

      alice.join("#names")
      bob.join("#names")

      alice.send("NAMES #names")
      alice.should_receive(/353.*#names.*Alice.*Bob/)          # RPL_NAMREPLY
      alice.should_receive(/366.*#names.*End of \/NAMES list/) # RPL_ENDOFNAMES

      alice.quit
      bob.quit
    end

    it "shows user privileges in NAMES" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16667, ssl: false)
      bob = env.create_client("Bob", port: 16667, ssl: false)

      alice.register
      bob.register

      alice.join("#privileges")
      bob.join("#privileges")

      # Give Bob voice
      alice.send("MODE #privileges +v Bob")
      alice.should_receive(/MODE #privileges.*\+v Bob/)

      alice.send("NAMES #privileges")
      alice.should_receive(/353.*#privileges.*@Alice.*\+Bob/) # @ for op, + for voice

      alice.quit
      bob.quit
    end

    it "handles WHO command for channels" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16667, ssl: false)
      alice.register
      alice.join("#who")

      alice.send("WHO #who")
      alice.should_receive(/352.*#who.*Alice/)             # RPL_WHOREPLY
      alice.should_receive(/315.*#who.*End of \/WHO list/) # RPL_ENDOFWHO

      alice.quit
    end
  end

  describe "channel bans and kicks" do
    it "handles KICK command" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16667, ssl: false)
      bob = env.create_client("Bob", port: 16667, ssl: false)

      alice.register
      bob.register

      alice.join("#kick")
      bob.join("#kick")

      # Alice kicks Bob
      alice.send("KICK #kick Bob :You're out!")
      alice.should_receive(/KICK #kick Bob :You're out!/)
      bob.should_receive(/KICK #kick Bob :You're out!/)

      alice.quit
      # Bob was already kicked
    end

    it "handles ban mode" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16667, ssl: false)
      bob = env.create_client("Bob", port: 16667, ssl: false)

      alice.register
      alice.join("#bans")

      # Set ban on Bob's hostmask
      alice.send("MODE #bans +b *!*@localhost")
      alice.should_receive(/MODE #bans.*\+b \*!\*@localhost/)

      # Bob tries to join
      bob.register
      bob.send("JOIN #bans")
      bob.should_receive(/474.*#bans.*Cannot join channel \(\+b\)/) # ERR_BANNEDFROMCHAN

      alice.quit
      bob.quit
    end

    it "enforces extended ban matches" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16667, ssl: false)
      bob = env.create_client("Bob", port: 16667, ssl: false)

      alice.register
      bob.register("blocked", "Blocked Realname")

      alice.join("#realban")
      alice.send("MODE #realban +b $r:*Blocked*")
      alice.should_receive(/MODE #realban.*\+b \$r:\*Blocked\*/)

      bob.send("JOIN #realban")
      bob.should_receive(/474.*#realban.*Cannot join channel \(\+b\)/)

      bob.join("#holding")
      alice.join("#joinban")
      alice.send("MODE #joinban +b ~j:#holding")
      alice.should_receive(/MODE #joinban.*\+b ~j:#holding/)

      bob.send("JOIN #joinban")
      bob.should_receive(/474.*#joinban.*Cannot join channel \(\+b\)/)

      alice.quit
      bob.quit
    end
  end

  describe "cross-server channel operations" do
    it "synchronizes channel state across servers" do
      env.setup_linked_servers(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)

      alice.register
      bob.register

      alice.join("#sync")
      bob.join("#sync")

      bob.should_receive(/353.*#sync.*Alice.*Bob/)
      alice.should_receive(/Bob.*JOIN.*#sync/)

      alice.quit
      bob.quit
    end

    it "propagates channel messages across servers" do
      env.setup_linked_servers(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)

      alice.register
      bob.register

      alice.join("#messages")
      bob.join("#messages")

      alice.privmsg("#messages", "cross-server channel message")
      assert_message_received(bob, "cross-server channel message", "Alice")

      alice.quit
      bob.quit
    end

    it "propagates channel modes across servers" do
      env.setup_linked_servers(ssl_enabled: false)

      alice = env.create_client("Alice", port: 16697)
      bob = env.create_client("Bob", port: 17697)

      alice.register
      bob.register

      alice.join("#remote-modes")
      bob.join("#remote-modes")

      alice.send("MODE #remote-modes +m")
      alice.should_receive(/MODE #remote-modes.*\+m/)
      bob.should_receive(/MODE #remote-modes.*\+m/)

      alice.quit
      bob.quit
    end
  end
end
