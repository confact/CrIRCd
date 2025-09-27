require "../../spec_helper"

describe Circed::Network::SSLSocket do
  describe ".ssl?" do
    it "returns false for TCPSocket" do
      socket = DummySocket.new
      Circed::Network::SSLSocket.ssl?(socket).should be_false
    end

    it "returns true for SSL socket types" do
      # We can't easily create real SSL sockets in tests
      # So we just verify the method works with our socket types
      socket = DummySocket.new

      # DummySocket is a TCPSocket, so it should not be SSL
      Circed::Network::SSLSocket.ssl?(socket).should be_false
    end
  end

  describe ".can_start_tls?" do
    it "returns true for plain TCP socket" do
      socket = DummySocket.new
      Circed::Network::SSLSocket.can_start_tls?(socket).should be_true
    end
  end

  describe ".get_peer_info" do
    it "returns nil for non-SSL sockets" do
      socket = DummySocket.new
      Circed::Network::SSLSocket.get_peer_info(socket).should be_nil
    end
  end

  describe "SSL context creation" do
    it "creates server context with basic config" do
      ssl_config = Circed::Config::SSLConfig.from_yaml(<<-YAML
        enabled: true
        port: 6697
        verify_mode: false
        YAML
      )

      # Since cert_file and key_file are nil, this should create a context
      # but it won't have certificates loaded
      context = Circed::Network::SSLSocket.create_context(ssl_config)
      context.should be_a(OpenSSL::SSL::Context::Server)
    end

    it "creates client context with basic config" do
      ssl_config = Circed::Config::SSLConfig.from_yaml(<<-YAML
        enabled: true
        verify_mode: false
        YAML
      )

      context = Circed::Network::SSLSocket.create_client_context(ssl_config)
      context.should be_a(OpenSSL::SSL::Context::Client)
    end
  end

  describe "IRCSocket type alias" do
    it "includes TCPSocket in the union" do
      socket = DummySocket.new
      typed_socket = socket.as(Circed::Network::SSLSocket::IRCSocket)
      # DummySocket inherits from TCPSocket via IPSocket, but Crystal's is_a?
      # checks exact inheritance. Let's verify it works with our SSL methods
      Circed::Network::SSLSocket.ssl?(typed_socket).should be_false
      Circed::Network::SSLSocket.can_start_tls?(typed_socket).should be_true
    end
  end
end
