require "../../spec_helper"

describe Circed::Config::SSLConfig do
  describe ".from_yaml" do
    it "parses basic SSL configuration" do
      yaml = <<-YAML
        enabled: true
        port: 6697
        cert_file: "/path/to/cert.pem"
        key_file: "/path/to/key.pem"
        verify_mode: false
        starttls: true
        YAML

      config = Circed::Config::SSLConfig.from_yaml(yaml)
      config.enabled?.should be_true
      config.port.should eq(6697)
      config.cert_file.should eq("/path/to/cert.pem")
      config.key_file.should eq("/path/to/key.pem")
      config.verify_mode?.should be_false
      config.starttls?.should be_true
    end

    it "uses default values when not specified" do
      yaml = <<-YAML
        enabled: false
        YAML

      config = Circed::Config::SSLConfig.from_yaml(yaml)
      config.enabled?.should be_false
      config.port.should eq(6697)
      config.cert_file.should be_nil
      config.key_file.should be_nil
      config.verify_mode?.should be_false
      config.starttls?.should be_true
      config.require_ssl_for_servers?.should be_false
    end

    it "parses complete SSL configuration" do
      yaml = <<-YAML
        enabled: true
        port: 6660
        cert_file: "/etc/ssl/server.crt"
        key_file: "/etc/ssl/server.key"
        ca_file: "/etc/ssl/ca.crt"
        verify_mode: true
        starttls: false
        require_ssl_for_servers: true
        YAML

      config = Circed::Config::SSLConfig.from_yaml(yaml)
      config.enabled?.should be_true
      config.port.should eq(6660)
      config.cert_file.should eq("/etc/ssl/server.crt")
      config.key_file.should eq("/etc/ssl/server.key")
      config.ca_file.should eq("/etc/ssl/ca.crt")
      config.verify_mode?.should be_true
      config.starttls?.should be_false
      config.require_ssl_for_servers?.should be_true
    end
  end

  describe "#valid?" do
    it "returns true when SSL is disabled" do
      config = Circed::Config::SSLConfig.from_yaml("enabled: false")
      config.valid?.should be_true
    end

    it "returns false when SSL is enabled but cert files are missing" do
      config = Circed::Config::SSLConfig.from_yaml(<<-YAML
        enabled: true
        cert_file: "/nonexistent/cert.pem"
        key_file: "/nonexistent/key.pem"
        YAML
      )
      config.valid?.should be_false
    end

    it "returns false when SSL is enabled but cert_file is nil" do
      config = Circed::Config::SSLConfig.from_yaml("enabled: true")
      config.valid?.should be_false
    end

    # Note: We can't easily test the file existence check in specs
    # without creating actual files, but the logic is straightforward
  end
end
