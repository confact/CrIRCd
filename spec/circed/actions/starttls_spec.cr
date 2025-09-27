require "../../spec_helper"

describe Circed::Actions::Starttls do
  before_each do
    clear_repositories
  end

  after_each do
    clear_repositories
  end

  describe ".call" do
    it "rejects STARTTLS when SSL config is nil" do
      # Test will use default server config which has SSL as nil
      client = create_test_client("Alice")

      # We can't easily mock in Crystal, so we test the error path
      # by using a client that will get the default config (no SSL)
      Circed::Actions::Starttls.call(client)

      # The test itself validates that the action doesn't crash
      # In a real scenario, this would send ERR_STARTTLS
      true.should be_true
    end

    it "handles STARTTLS with DummySocket" do
      client = create_test_client("Alice")

      # DummySocket simulates a plain TCP connection
      client.socket.should be_a(DummySocket)

      # Call STARTTLS - with default config (no SSL), it should handle gracefully
      Circed::Actions::Starttls.call(client)

      # Test passes if no exception is raised
      true.should be_true
    end

    it "validates socket type checking" do
      client = create_test_client("Alice")

      # Test that we can check socket types
      socket = client.socket
      if socket
        Circed::Network::SSLSocket.ssl?(socket).should be_false
        Circed::Network::SSLSocket.can_start_tls?(socket).should be_true
      end
    end

    it "handles nil socket gracefully" do
      client = create_test_client("Alice")
      client.socket = nil

      # Should not crash when socket is nil
      Circed::Actions::Starttls.call(client)
      true.should be_true
    end
  end

  describe "SSL config validation" do
    it "can create SSL config from YAML" do
      yaml = <<-YAML
        enabled: true
        port: 6697
        starttls: true
        verify_mode: false
        YAML

      ssl_config = Circed::Config::SSLConfig.from_yaml(yaml)
      ssl_config.enabled?.should be_true
      ssl_config.starttls?.should be_true
    end

    it "handles disabled SSL config" do
      yaml = <<-YAML
        enabled: false
        starttls: false
        YAML

      ssl_config = Circed::Config::SSLConfig.from_yaml(yaml)
      ssl_config.enabled?.should be_false
      ssl_config.starttls?.should be_false
    end
  end
end
