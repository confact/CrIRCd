require "../../spec_helper"

describe Circed::Config do
  describe "SSL integration" do
    it "includes SSL configuration" do
      yaml = <<-YAML
        host: "localhost"
        port: 6667
        network: "TestNet"
        max_users: 100
        link_password: "test"
        ssl:
          enabled: true
          port: 6697
          starttls: true
        YAML

      config = Circed::Config.from_yaml(yaml)
      ssl_config = config.ssl
      ssl_config.should_not be_nil

      if ssl_config
        ssl_config.enabled?.should be_true
        ssl_config.port.should eq(6697)
        ssl_config.starttls?.should be_true
      end
    end

    it "works without SSL configuration" do
      yaml = <<-YAML
        host: "localhost"
        port: 6667
        network: "TestNet"
        max_users: 100
        link_password: "test"
        YAML

      config = Circed::Config.from_yaml(yaml)
      config.ssl.should be_nil
    end

    describe "#validate_ssl!" do
      it "does not raise when SSL is not configured" do
        yaml = <<-YAML
          host: "localhost"
          port: 6667
          network: "TestNet"
          max_users: 100
          link_password: "test"
          YAML

        config = Circed::Config.from_yaml(yaml)
        # Should not raise exception - if it doesn't raise, test passes
        config.validate_ssl!
        # Test passes if we reach this line without exception
        true.should be_true
      end

      it "does not raise when SSL is disabled" do
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
        # Should not raise exception - if it doesn't raise, test passes
        config.validate_ssl!
        # Test passes if we reach this line without exception
        true.should be_true
      end

      it "raises when SSL is enabled but invalid" do
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
    end
  end
end
