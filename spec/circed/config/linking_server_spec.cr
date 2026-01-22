require "../../spec_helper"

describe Circed::LinkedServer do
  describe ".from_yaml" do
    it "parses basic server configuration" do
      yaml = <<-YAML
        host: "irc.example.com"
        port: 6667
        link_password: "secret123"
        YAML

      server = Circed::LinkedServer.from_yaml(yaml)
      server.host.should eq("irc.example.com")
      server.port.should eq(6667)
      server.link_password.should eq("secret123")
      server.use_ssl?.should be_false
      server.verify_ssl?.should be_false
    end

    it "parses SSL-enabled server configuration" do
      yaml = <<-YAML
        host: "secure.irc.example.com"
        port: 6697
        link_password: "secret123"
        use_ssl: true
        verify_ssl: true
        YAML

      server = Circed::LinkedServer.from_yaml(yaml)
      server.host.should eq("secure.irc.example.com")
      server.port.should eq(6697)
      server.link_password.should eq("secret123")
      server.use_ssl?.should be_true
      server.verify_ssl?.should be_true
    end

    it "uses default SSL values when not specified" do
      yaml = <<-YAML
        host: "irc.example.com"
        port: 6667
        link_password: "secret123"
        use_ssl: false
        YAML

      server = Circed::LinkedServer.from_yaml(yaml)
      server.use_ssl?.should be_false
      server.verify_ssl?.should be_false
    end
  end

  describe "SSL configuration combinations" do
    it "allows SSL without verification" do
      yaml = <<-YAML
        host: "irc.example.com"
        port: 6697
        link_password: "secret123"
        use_ssl: true
        verify_ssl: false
        YAML

      server = Circed::LinkedServer.from_yaml(yaml)
      server.use_ssl?.should be_true
      server.verify_ssl?.should be_false
    end

    it "allows verification to be true when SSL is enabled" do
      yaml = <<-YAML
        host: "irc.example.com"
        port: 6697
        link_password: "secret123"
        use_ssl: true
        verify_ssl: true
        YAML

      server = Circed::LinkedServer.from_yaml(yaml)
      server.use_ssl?.should be_true
      server.verify_ssl?.should be_true
    end
  end
end
