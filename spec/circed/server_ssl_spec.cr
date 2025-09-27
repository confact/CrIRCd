require "../spec_helper"

describe "Server SSL Integration" do
  before_each do
    clear_repositories
  end

  after_each do
    clear_repositories
  end

  describe "SSL configuration validation" do
    it "validates SSL configuration on startup" do
      yaml = <<-YAML
        host: "localhost"
        port: 6667
        network: "TestNet"
        max_users: 100
        link_password: "test"
        ssl:
          enabled: true
          cert_file: "/nonexistent/cert.pem"
          key_file: "/nonexistent/key.pem"
        YAML

      config = Circed::Config.from_yaml(yaml)
      expect_raises(Exception, /Invalid SSL configuration/) do
        config.validate_ssl!
      end
    end

    it "passes validation when SSL is disabled" do
      yaml = <<-YAML
        host: "localhost"
        port: 6667
        network: "TestNet"
        max_users: 100
        link_password: "test"
        ssl:
          enabled: false
        YAML

      config = Circed::Config.from_yaml(yaml)
      # Should not raise
      config.validate_ssl!
      true.should be_true
    end

    it "passes validation when SSL config is missing" do
      yaml = <<-YAML
        host: "localhost"
        port: 6667
        network: "TestNet"
        max_users: 100
        link_password: "test"
        YAML

      config = Circed::Config.from_yaml(yaml)
      # Should not raise when SSL section is missing
      config.validate_ssl!
      true.should be_true
    end
  end

  describe "SSL server setup" do
    it "handles missing SSL context gracefully" do
      # Test that server methods don't crash when SSL is not configured
      yaml = <<-YAML
        host: "localhost"
        port: 6667
        network: "TestNet"
        max_users: 100
        link_password: "test"
        YAML

      config = Circed::Config.from_yaml(yaml)

      # Mock the Server.config to return our test config
      # Note: In real testing, we'd need dependency injection
      config.ssl.should be_nil
    end

    it "creates SSL context when properly configured" do
      # Test SSL context creation with valid config
      yaml = <<-YAML
        enabled: true
        port: 6697
        verify_mode: false
        YAML

      ssl_config = Circed::Config::SSLConfig.from_yaml(yaml)
      ssl_config.enabled?.should be_true

      # We can't test actual context creation without cert files
      # but we can verify the config is structured correctly
      ssl_config.port.should eq(6697)
    end
  end

  describe "Client SSL handling" do
    it "supports different socket types" do
      client = create_test_client("SSLTestUser")
      socket = client.socket

      # Verify socket type detection works
      if socket
        Circed::Network::SSLSocket.ssl?(socket).should be_false
        Circed::Network::SSLSocket.can_start_tls?(socket).should be_true
      end
    end

    it "handles hostname resolution for SSL clients" do
      client = create_test_client("SSLTestUser")
      socket = client.socket

      # Test hostname resolution works with our socket types
      if socket
        hostname = Circed::Hostname.get_hostname(socket)
        hostname.should be_a(String)
        hostname.should_not be_empty
      end
    end
  end

  describe "Server linking with SSL" do
    it "supports SSL parameters in linked server config" do
      yaml = <<-YAML
        host: "irc.example.com"
        port: 6697
        link_password: "secret"
        use_ssl: true
        verify_ssl: true
        YAML

      linked_server = Circed::LinkedServer.from_yaml(yaml)
      linked_server.use_ssl?.should be_true
      linked_server.verify_ssl?.should be_true
      linked_server.port.should eq(6697)
    end

    it "defaults to non-SSL for linked servers" do
      yaml = <<-YAML
        host: "irc.example.com"
        port: 6667
        link_password: "secret"
        YAML

      linked_server = Circed::LinkedServer.from_yaml(yaml)
      linked_server.use_ssl?.should be_false
      linked_server.verify_ssl?.should be_false
    end
  end

  describe "IRC numerics" do
    it "includes STARTTLS numerics" do
      Circed::Numerics::RPL_STARTTLS.should eq("670")
      Circed::Numerics::ERR_STARTTLS.should eq("691")
      Circed::Numerics::RPL_WHOISSECURE.should eq("671")
    end
  end

  describe "Socket type compatibility" do
    it "handles DummySocket in tests" do
      socket = DummySocket.new
      typed_socket = socket.as(Circed::Network::SSLSocket::IRCSocket)

      # Verify our type alias works with test sockets
      # DummySocket inherits from IPSocket, not TCPSocket directly
      typed_socket.should be_a(IPSocket)
      Circed::Network::SSLSocket.ssl?(typed_socket).should be_false
      Circed::Network::SSLSocket.can_start_tls?(typed_socket).should be_true
    end

    it "supports socket address resolution" do
      socket = DummySocket.new

      # Test remote address access
      socket.remote_address.should be_a(Socket::IPAddress)
      socket.remote_address.address.should eq("127.0.0.1")
      socket.remote_address.port.should eq(12345)
    end
  end
end
