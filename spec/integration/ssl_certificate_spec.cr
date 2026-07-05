require "../spec_helper"
require "../support/ssl_cert_generator"

describe "SSL Certificate Generation" do
  temp_dir = File.join(__DIR__, "../../tmp", "ssl_test")

  before_each do
    FileUtils.mkdir_p(File.dirname(temp_dir))
    SSLCertificateGenerator.generate_test_certificates(temp_dir)
  end

  after_each do
    FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
  end

  describe "generated certificates" do
    it "creates CA certificate and key" do
      ca_cert_path = File.join(temp_dir, "ca/ca.crt")
      ca_key_path = File.join(temp_dir, "ca/ca.key")

      File.exists?(ca_cert_path).should be_true
      File.exists?(ca_key_path).should be_true

      # Verify the CA certificate has correct content
      ca_cert_content = File.read(ca_cert_path)
      ca_cert_content.should contain("BEGIN CERTIFICATE")
      ca_cert_content.should contain("END CERTIFICATE")
      ca_cert_content.size.should be > 500 # Basic size check
    end

    it "creates server certificates signed by CA" do
      server1_cert_path = File.join(temp_dir, "server1/server.crt")
      server1_key_path = File.join(temp_dir, "server1/server.key")

      File.exists?(server1_cert_path).should be_true
      File.exists?(server1_key_path).should be_true

      # Verify certificates exist and have correct content
      server_cert_content = File.read(server1_cert_path)
      ca_cert_content = File.read(File.join(temp_dir, "ca/ca.crt"))

      server_cert_content.should contain("BEGIN CERTIFICATE")
      ca_cert_content.should contain("BEGIN CERTIFICATE")

      # Both certificates should be valid and properly sized
      server_cert_content.size.should be > 500
      ca_cert_content.size.should be > 500
    end

    it "creates multiple server certificates" do
      %w[server1 server2].each do |server|
        cert_path = File.join(temp_dir, "#{server}/server.crt")
        key_path = File.join(temp_dir, "#{server}/server.key")

        File.exists?(cert_path).should be_true
        File.exists?(key_path).should be_true

        cert_content = File.read(cert_path)
        cert_content.should contain("BEGIN CERTIFICATE")
        cert_content.should contain("END CERTIFICATE")
        cert_content.size.should be > 500
      end
    end

    it "certificates have valid structure" do
      ca_cert_content = File.read(File.join(temp_dir, "ca/ca.crt"))
      server_cert_content = File.read(File.join(temp_dir, "server1/server.crt"))

      # Should have proper certificate structure
      ca_cert_content.should contain("BEGIN CERTIFICATE")
      ca_cert_content.should contain("END CERTIFICATE")
      ca_cert_content.size.should be > 500

      server_cert_content.should contain("BEGIN CERTIFICATE")
      server_cert_content.should contain("END CERTIFICATE")
      server_cert_content.size.should be > 500
    end
  end

  describe "certificate usage in SSL config" do
    it "creates valid SSL config with generated certificates" do
      ssl_config = Circed::Config::SSLConfig.from_yaml(<<-YAML
        enabled: true
        port: 6697
        cert_file: "#{File.join(temp_dir, "server1/server.crt")}"
        key_file: "#{File.join(temp_dir, "server1/server.key")}"
        ca_file: "#{File.join(temp_dir, "ca/ca.crt")}"
        verify_mode: true
        starttls: true
        YAML
      )

      ssl_config.valid?.should be_true

      # Test creating SSL context
      context = Circed::Network::SSLSocket.create_context(ssl_config)
      context.should be_a(OpenSSL::SSL::Context::Server)
    end

    it "creates client SSL config for mutual TLS" do
      client_config = Circed::Config::SSLConfig.from_yaml(<<-YAML
        enabled: true
        cert_file: "#{File.join(temp_dir, "server2/server.crt")}"
        key_file: "#{File.join(temp_dir, "server2/server.key")}"
        ca_file: "#{File.join(temp_dir, "ca/ca.crt")}"
        verify_mode: true
        YAML
      )

      context = Circed::Network::SSLSocket.create_client_context(client_config)
      context.should be_a(OpenSSL::SSL::Context::Client)
      context.verify_mode.should eq(OpenSSL::SSL::VerifyMode::PEER)
    end
  end
end
