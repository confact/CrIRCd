require "../spec_helper"

describe "IRC Protocol Integration" do
  env = TestEnvironment.new

  after_each do
    env.teardown
  end

  describe "user registration and authentication" do
    it "completes full registration sequence" do
      env.setup_single_server(ssl_enabled: false)

      client = env.create_client("TestUser", port: 16667, ssl: false)
      client.register

      # Should be able to perform IRC operations
      client.send("PING :test")
      client.should_receive(/PONG.*test/)

      client.quit
    end

    it "handles nick collision" do
      env.setup_single_server(ssl_enabled: false)

      alice1 = env.create_client("Alice")
      alice1.register
      assert_welcome_sequence(alice1)

      alice2 = env.create_client("Alice")
      alice2.send("NICK Alice")
      alice2.should_receive(/433.*Alice.*Nickname is already in use/) # ERR_NICKNAMEINUSE

      alice1.quit
      alice2.quit
    end

    it "handles invalid nicknames" do
      env.setup_single_server(ssl_enabled: false)

      client = env.create_client("Test User") # Invalid nick with space
      client.send("NICK Test User")
      client.should_receive(/432.*Erroneous nickname/) # ERR_ERRONEUSNICKNAME

      client.quit
    end

    it "requires registration before IRC commands" do
      env.setup_single_server(ssl_enabled: false)

      client = env.create_client("TestUser", port: 16667, ssl: false)

      # Try to join channel before registering
      client.send("JOIN #test")
      client.should_receive(/451.*You have not registered/) # ERR_NOTREGISTERED

      # Now register properly
      client.register
      assert_welcome_sequence(client)

      # Now JOIN should work
      client.join("#test")
      assert_channel_joined(client, "#test")

      client.quit
    end
  end

  describe "channel operations" do
    it "creates and joins channels" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice")
      alice.register

      # Create channel
      alice.join("#newchannel")
      assert_channel_joined(alice, "#newchannel")

      # Should become operator
      alice.should_receive(/MODE #newchannel.*\+o Alice/)

      alice.quit
    end

    it "handles channel topics" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice")
      alice.register
      alice.join("#test")

      # Set topic
      alice.send("TOPIC #test :This is a test topic")
      alice.should_receive(/TOPIC #test :This is a test topic/)

      # Query topic
      bob = env.create_client("Bob")
      bob.register
      bob.join("#test")
      bob.should_receive(/332.*#test.*This is a test topic/) # RPL_TOPIC

      alice.quit
      bob.quit
    end

    it "handles channel modes" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice")
      alice.register
      alice.join("#test")

      # Set channel mode
      alice.send("MODE #test +m") # Moderated
      alice.should_receive(/MODE #test.*\+m/)

      alice.quit
    end

    it "handles user permissions in channels" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice")
      bob = env.create_client("Bob")

      alice.register
      bob.register

      alice.join("#test")
      bob.join("#test")

      # Alice gives Bob operator status
      alice.send("MODE #test +o Bob")
      alice.should_receive(/MODE #test.*\+o Bob/)
      bob.should_receive(/MODE #test.*\+o Bob/)

      alice.quit
      bob.quit
    end
  end

  describe "private messaging" do
    it "sends private messages between users" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice")
      bob = env.create_client("Bob")

      alice.register
      bob.register

      # Alice sends private message to Bob
      message = "Hello Bob, this is a private message!"
      alice.privmsg("Bob", message)

      assert_message_received(bob, message, "Alice")

      alice.quit
      bob.quit
    end

    it "handles private messages to non-existent users" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice")
      alice.register

      alice.privmsg("NonExistentUser", "Hello")
      alice.should_receive(/401.*NonExistentUser.*No such nick/) # ERR_NOSUCHNICK

      alice.quit
    end
  end

  describe "user modes and away status" do
    it "grants IRC operator mode with OPER" do
      env.setup_single_server(ssl_enabled: false) do |config|
        config.add_operator("global", "secret", ["*!alice@localhost"])
      end

      alice = env.create_client("Alice")
      alice.register("alice")

      alice.send("OPER global secret")
      alice.should_receive(/381.*Alice.*You are now an IRC operator/)
      alice.should_receive(/MODE Alice \+o/)

      alice.send("MODE Alice +O")
      alice.send("MODE Alice")
      alice.should_receive(/221.*Alice.*\+o/)

      alice.quit
    end

    it "handles AWAY command" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice")
      alice.register

      # Set away
      alice.send("AWAY :Gone fishing")
      alice.should_receive(/306.*You have been marked as being away/) # RPL_NOWAWAY

      # Remove away
      alice.send("AWAY")
      alice.should_receive(/305.*You are no longer marked as being away/) # RPL_UNAWAY

      alice.quit
    end

    it "shows away status in WHOIS" do
      env.setup_single_server(ssl_enabled: false)

      alice = env.create_client("Alice")
      bob = env.create_client("Bob")

      alice.register
      bob.register

      alice.send("AWAY :Testing away")
      alice.should_receive(/306/) # RPL_NOWAWAY

      # Bob checks Alice's status
      bob.send("WHOIS Alice")
      bob.should_receive(/301.*Alice.*Testing away/) # RPL_AWAY

      alice.quit
      bob.quit
    end
  end

  describe "PING/PONG handling" do
    it "responds to server PING" do
      env.setup_single_server(ssl_enabled: false)

      client = env.create_client("TestUser", port: 16667, ssl: false)
      client.register

      # Server might send PING
      client.send("PING :test")
      client.should_receive(/PONG.*test/)

      client.quit
    end

    it "handles client PING" do
      env.setup_single_server(ssl_enabled: false)

      client = env.create_client("TestUser", port: 16667, ssl: false)
      client.register

      client.send("PING :client_test")
      client.should_receive(/PONG.*client_test/)

      client.quit
    end
  end

  describe "error handling" do
    it "handles unknown commands gracefully" do
      env.setup_single_server(ssl_enabled: false)

      client = env.create_client("TestUser", port: 16667, ssl: false)
      client.register

      client.send("UNKNOWN_COMMAND test")
      client.should_receive(/421.*UNKNOWN_COMMAND.*Unknown command/) # ERR_UNKNOWNCOMMAND

      client.quit
    end

    it "handles malformed commands" do
      env.setup_single_server(ssl_enabled: false)

      client = env.create_client("TestUser", port: 16667, ssl: false)
      client.register

      # Send malformed command
      client.send("PRIVMSG")                                       # Missing parameters
      client.should_receive(/461.*PRIVMSG.*Not enough parameters/) # ERR_NEEDMOREPARAMS

      client.quit
    end
  end
end
