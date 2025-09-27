require "../spec_helper"

describe "SSL Connection Integration" do
  env = TestEnvironment.new

  after_each do
    env.teardown
  end

  describe "SSL client connections" do
    it "accepts SSL connections on SSL port" do
      env.setup_single_server(ssl_enabled: true)

      client = env.create_client("TestUser", ssl: true)
      client.register

      assert_welcome_sequence(client)
      client.quit
    end

    it "rejects non-SSL connections on SSL port" do
      env.setup_single_server(ssl_enabled: true)

      expect_raises(Exception) do
        env.create_client("TestUser", ssl: false)
      end
    end

    it "handles multiple concurrent SSL connections" do
      env.setup_single_server(ssl_enabled: true)

      clients = (1..5).map do |i|
        client = env.create_client("User#{i}", ssl: true)
        client.register
        assert_welcome_sequence(client)
        client
      end

      # All clients should be connected
      clients.each do |client|
        client.send("PING :test")
        client.should_receive(/PONG.*test/)
      end

      clients.each(&.quit)
    end

    it "maintains SSL encryption throughout session" do
      env.setup_single_server(ssl_enabled: true)

      client = env.create_client("TestUser", ssl: true)
      client.register

      assert_welcome_sequence(client)

      # Test various IRC commands over SSL
      client.join("#test")
      assert_channel_joined(client, "#test")

      client.privmsg("#test", "Hello SSL world!")
      client.send("TOPIC #test :SSL Test Topic")
      client.should_receive(/TOPIC #test :SSL Test Topic/)

      client.quit
    end
  end

  describe "SSL certificate verification" do
    it "connects with self-signed certificates" do
      env.setup_single_server(ssl_enabled: true)

      client = env.create_client("TestUser", ssl: true)
      client.register

      assert_welcome_sequence(client)
      client.quit
    end

    it "handles SSL handshake properly" do
      env.setup_single_server(ssl_enabled: true)

      # Create SSL socket and verify handshake
      tcp = TCPSocket.new("localhost", 16697)
      context = OpenSSL::SSL::Context::Client.new
      context.verify_mode = OpenSSL::SSL::VerifyMode::NONE

      ssl_socket = OpenSSL::SSL::Socket::Client.new(tcp, context, sync_close: true)

      # Should successfully complete handshake
      ssl_socket.cipher.should_not be_nil
      ssl_socket.tls_version.should_not be_nil

      ssl_socket.close
    end
  end

  describe "SSL performance and stability" do
    it "handles rapid connect/disconnect cycles" do
      env.setup_single_server(ssl_enabled: true)

      10.times do |i|
        client = env.create_client("User#{i}", ssl: true)
        client.register
        client.should_receive(/001.*Welcome/)
        client.quit
      end
    end

    it "maintains performance with SSL overhead" do
      env.setup_single_server(ssl_enabled: true)

      client = env.create_client("TestUser", ssl: true)
      client.register

      start_time = Time.monotonic

      # Send multiple commands rapidly
      100.times do |i|
        client.send("PING :test#{i}")
        client.should_receive(/PONG.*test#{i}/)
      end

      elapsed = Time.monotonic - start_time
      elapsed.should be < 5.seconds # Should handle 100 ping/pongs in under 5 seconds

      client.quit
    end
  end
end
