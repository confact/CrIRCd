require "../../spec_helper"

describe Circed::Config::DNSConfig do
  it "uses production-safe defaults" do
    config = Circed::Config::DNSConfig.new

    config.enabled?.should be_true
    config.server.should eq("8.8.8.8")
    config.port.should eq(53)
    config.workers.should eq(4)
    config.registration_wait_ms.should eq(100)
  end

  it "loads DNS settings from YAML" do
    config = Circed::Config::DNSConfig.from_yaml(<<-YAML
      enabled: false
      server: "1.1.1.1"
      port: 53
      workers: 8
      queue_size: 2048
      timeout_seconds: 2
      registration_wait_ms: 250
      cache_ttl_seconds: 120
      negative_cache_ttl_seconds: 30
      YAML
    )

    config.enabled?.should be_false
    config.server.should eq("1.1.1.1")
    config.workers.should eq(8)
    config.queue_size.should eq(2048)
    config.timeout_seconds.should eq(2)
    config.registration_wait_ms.should eq(250)
    config.cache_ttl_seconds.should eq(120)
    config.negative_cache_ttl_seconds.should eq(30)
  end
end
