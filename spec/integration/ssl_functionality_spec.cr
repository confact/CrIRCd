require "../spec_helper"

require "../support/ssl_cert_generator"

describe "Real SSL Connection Integration" do
  temp_dir = File.join(__DIR__, "../../tmp", "ssl_test")

  before_each do
    FileUtils.mkdir_p(File.dirname(temp_dir))
    SSLCertificateGenerator.generate_test_certificates(temp_dir)
  end

  after_each do
    FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
  end

  describe "SSL server functionality" do
    it "creates SSL context successfully" do
      ssl_config = Circed::Config::SSLConfig.from_yaml(<<-YAML
        enabled: true
        port: 6697
        cert_file: "#{File.join(temp_dir, "server1/server.crt")}"
        key_file: "#{File.join(temp_dir, "server1/server.key")}"
        verify_mode: false
        starttls: true
        YAML
      )

      context = Circed::Network::SSLSocket.create_context(ssl_config)
      context.should be_a(OpenSSL::SSL::Context::Server)
      # Note: Crystal's OpenSSL wrapper doesn't expose direct access to loaded certificates
      # But the context creation would fail if certificates weren't loaded properly
    end

    it "validates SSL certificate files exist" do
      ssl_config = Circed::Config::SSLConfig.from_yaml(<<-YAML
        enabled: true
        port: 6697
        cert_file: "#{File.join(temp_dir, "server1/server.crt")}"
        key_file: "#{File.join(temp_dir, "server1/server.key")}"
        verify_mode: false
        YAML
      )

      ssl_config.valid?.should be_true
    end

    it "rejects invalid SSL configuration" do
      ssl_config = Circed::Config::SSLConfig.from_yaml(<<-YAML
        enabled: true
        port: 6697
        cert_file: "/nonexistent/cert.crt"
        key_file: "/nonexistent/key.key"
        verify_mode: false
        YAML
      )

      ssl_config.valid?.should be_false
    end
  end

  describe "SSL client context creation" do
    it "creates client SSL context" do
      ssl_config = Circed::Config::SSLConfig.from_yaml(<<-YAML
        enabled: true
        verify_mode: false
        ca_file: "#{File.join(temp_dir, "ca/ca.crt")}"
        YAML
      )

      context = Circed::Network::SSLSocket.create_client_context(ssl_config)
      context.should be_a(OpenSSL::SSL::Context::Client)
      context.verify_mode.should eq(OpenSSL::SSL::VerifyMode::NONE)
    end

    it "configures client certificate verification" do
      ssl_config = Circed::Config::SSLConfig.from_yaml(<<-YAML
        enabled: true
        verify_mode: true
        ca_file: "#{File.join(temp_dir, "ca/ca.crt")}"
        cert_file: "#{File.join(temp_dir, "server1/server.crt")}"
        key_file: "#{File.join(temp_dir, "server1/server.key")}"
        YAML
      )

      context = Circed::Network::SSLSocket.create_client_context(ssl_config)
      context.verify_mode.should eq(OpenSSL::SSL::VerifyMode::PEER)
      # Note: CA certificates are loaded but not directly accessible through the context
    end
  end

  describe "SSL socket operations" do
    it "detects SSL socket types correctly" do
      tcp_socket = DummySocket.new
      Circed::Network::SSLSocket.ssl?(tcp_socket).should be_false
      Circed::Network::SSLSocket.can_start_tls?(tcp_socket).should be_true
    end

    it "handles SSL configuration with mutual TLS" do
      ssl_config = Circed::Config::SSLConfig.from_yaml(<<-YAML
        enabled: true
        port: 6697
        cert_file: "#{File.join(temp_dir, "server1/server.crt")}"
        key_file: "#{File.join(temp_dir, "server1/server.key")}"
        ca_file: "#{File.join(temp_dir, "ca/ca.crt")}"
        verify_mode: true
        starttls: true
        require_ssl_for_servers: true
        YAML
      )

      ssl_config.enabled?.should be_true
      ssl_config.verify_mode?.should be_true
      ssl_config.starttls?.should be_true
      ssl_config.require_ssl_for_servers?.should be_true
      ssl_config.valid?.should be_true
    end
  end

  describe "STARTTLS configuration" do
    it "enables STARTTLS when configured" do
      ssl_config = Circed::Config::SSLConfig.from_yaml(<<-YAML
        enabled: true
        starttls: true
        verify_mode: false
        YAML
      )

      ssl_config.starttls?.should be_true
    end

    it "disables STARTTLS when configured" do
      ssl_config = Circed::Config::SSLConfig.from_yaml(<<-YAML
        enabled: true
        starttls: false
        verify_mode: false
        YAML
      )

      ssl_config.starttls?.should be_false
    end
  end
end
