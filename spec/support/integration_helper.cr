# Integration Test Helper for IRC Server
# Provides utilities for testing full IRC flows with real server instances

require "socket"
require "openssl"
require "spec"
require "yaml"

module IntegrationHelper
  # Test server manager
  class TestServer
    getter process : Process?
    getter port : Int32
    getter ssl_port : Int32
    getter config_file : String
    getter log_file : String

    def initialize(@name : String, @port : Int32, @ssl_port : Int32)
      @config_file = "spec/fixtures/#{@name}_config.yml"
      @log_file = "spec/logs/#{@name}.log"
    end

    def start
      # Build server if needed
      build_server

      # Start server process
      @process = Process.new(
        command: "./circed_test",
        args: [@config_file],
        input: Process::Redirect::Close,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      )

      # Wait for server to be ready
      wait_for_ready
      self
    end

    def stop
      if proc = @process
        proc.signal(Signal::TERM)
        Fiber.yield # Give the process time to handle the signal
        begin
          proc.wait
        rescue
          # Process may have already exited
        end
        @process = nil
      end
    end

    def running?
      return false unless proc = @process
      Process.exists?(proc.pid)
    rescue
      false
    end

    def pid
      @process.try(&.pid)
    end

    private def build_server
      unless File.exists?("./circed_test")
        system("crystal build src/circed.cr -o circed_test")
      end
    end

    private def wait_for_ready(timeout = 5.seconds)
      deadline = Time.monotonic + timeout

      loop do
        begin
          socket = TCPSocket.new("localhost", @port)
          socket.close
          return true
        rescue
          if Time.monotonic > deadline
            raise "Server #{@name} failed to start within #{timeout}"
          end
          sleep 0.1.seconds
        end
      end
    end
  end

  # IRC Test Client for integration tests
  class TestClient
    getter nickname : String
    getter socket : IO
    getter responses : Array(String) = [] of String
    getter? ssl : Bool

    def initialize(@nickname : String, @host : String = "localhost", @port : Int32 = 6667, @ssl : Bool = true)
      @socket = connect
    end

    private def connect : IO
      tcp = TCPSocket.new(@host, @port)

      if @ssl
        context = OpenSSL::SSL::Context::Client.new
        context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
        OpenSSL::SSL::Socket::Client.new(tcp, context, sync_close: true)
      else
        tcp
      end
    end

    def send(command : String)
      @socket.write("#{command}\r\n".to_slice)
      @socket.flush
      self
    end

    def register(username = nil, realname = nil)
      username ||= @nickname.downcase
      realname ||= "Test User #{@nickname}"

      send("NICK #{@nickname}")
      send("USER #{username} 0 * :#{realname}")
      wait_for_registration
      self
    end

    def join(channel : String)
      send("JOIN #{channel}")
      wait_for_response(/JOIN/)
      self
    end

    def privmsg(target : String, message : String)
      send("PRIVMSG #{target} :#{message}")
      self
    end

    def wait_for_response(pattern : Regex, timeout = 2.seconds) : String?
      deadline = Time.monotonic + timeout

      while Time.monotonic < deadline
        if response = read_line(0.1.seconds)
          @responses << response

          # Auto-respond to PING
          if response.starts_with?("PING")
            pong_target = response.split(" ", 2)[1]?
            send("PONG #{pong_target}")
          end

          return response if response.matches?(pattern)
        end
      end

      nil
    end

    def wait_for_registration(timeout = 2.seconds)
      wait_for_response(/001.*Welcome/, timeout)
    end

    def read_line(timeout = 1.second) : String?
      # Use fiber-based timeout
      channel = Channel(String?).new

      spawn do
        begin
          if line = @socket.gets
            channel.send(line.strip)
          else
            channel.send(nil)
          end
        rescue
          channel.send(nil)
        end
      end

      select
      when result = channel.receive
        result
      when timeout(timeout)
        nil
      end
    end

    def expect_response(pattern : Regex, timeout = 2.seconds)
      response = wait_for_response(pattern, timeout)
      response.should_not be_nil
      response
    end

    def should_receive(pattern : Regex, timeout = 2.seconds)
      expect_response(pattern, timeout)
    end

    def should_not_receive(pattern : Regex, timeout = 1.second)
      response = wait_for_response(pattern, timeout)
      response.should be_nil
    end

    def quit(message = "Test complete")
      send("QUIT :#{message}")
      close
    end

    def close
      @socket.close unless @socket.closed?
    end
  end

  # Server configuration builder for tests
  class ConfigBuilder
    @config = {} of YAML::Any => YAML::Any

    def self.build(name : String, &)
      builder = new(name)
      yield builder
      builder.save
    end

    def initialize(@name : String)
      @config = {
        YAML::Any.new("host")          => YAML::Any.new("0.0.0.0"),
        YAML::Any.new("port")          => YAML::Any.new(16667),
        YAML::Any.new("network")       => YAML::Any.new("TestNetwork"),
        YAML::Any.new("max_users")     => YAML::Any.new(100),
        YAML::Any.new("server_name")   => YAML::Any.new(@name),
        YAML::Any.new("link_password") => YAML::Any.new("test_password"),
      }
    end

    def port(value : Int32)
      @config[YAML::Any.new("port")] = YAML::Any.new(value)
      self
    end

    def ssl_port(value : Int32)
      ssl_config[YAML::Any.new("port")] = YAML::Any.new(value)
      self
    end

    def ssl_enabled(value : Bool)
      ssl_config[YAML::Any.new("enabled")] = YAML::Any.new(value)
      self
    end

    def ssl_cert(cert_file : String, key_file : String)
      ssl_config[YAML::Any.new("cert_file")] = YAML::Any.new(cert_file)
      ssl_config[YAML::Any.new("key_file")] = YAML::Any.new(key_file)
      self
    end

    def add_linked_server(host : String, port : Int32, use_ssl : Bool = true)
      linked_servers << YAML::Any.new({
        YAML::Any.new("host")          => YAML::Any.new(host),
        YAML::Any.new("port")          => YAML::Any.new(port),
        YAML::Any.new("link_password") => YAML::Any.new("test_password"),
        YAML::Any.new("use_ssl")       => YAML::Any.new(use_ssl),
        YAML::Any.new("verify_ssl")    => YAML::Any.new(false),
      })
      self
    end

    private def ssl_config
      ssl_key = YAML::Any.new("ssl")
      @config[ssl_key] ||= YAML::Any.new({} of YAML::Any => YAML::Any)
      @config[ssl_key].as_h
    end

    private def linked_servers
      servers_key = YAML::Any.new("linked_servers")
      @config[servers_key] ||= YAML::Any.new([] of YAML::Any)
      @config[servers_key].as_a
    end

    def save : String
      path = "spec/fixtures/#{@name}_config.yml"
      Dir.mkdir_p("spec/fixtures")
      File.write(path, @config.to_yaml)
      path
    end
  end

  # Test assertions for IRC protocol
  module Assertions
    def assert_irc_numeric(response : String, numeric : Int32)
      response.should match(/:\S+ #{numeric.to_s.rjust(3, '0')} /)
    end

    def assert_irc_command(response : String, command : String)
      response.should match(/:\S+ #{command} /)
    end

    def assert_welcome_sequence(client : TestClient)
      client.should_receive(/001.*Welcome/)            # RPL_WELCOME
      client.should_receive(/002.*Your host/)          # RPL_YOURHOST
      client.should_receive(/003.*created/)            # RPL_CREATED
      client.should_receive(/004.*#{client.nickname}/) # RPL_MYINFO
    end

    def assert_channel_joined(client : TestClient, channel : String)
      client.should_receive(/JOIN.*#{channel}/)
    end

    def assert_message_received(client : TestClient, message : String, from : String? = nil)
      pattern = if from
                  /#{from}.*PRIVMSG.*#{message}/
                else
                  /PRIVMSG.*#{message}/
                end
      client.should_receive(pattern)
    end
  end

  # Test environment manager with automatic setup/teardown
  class TestEnvironment
    getter servers = [] of TestServer
    getter clients = [] of TestClient

    def setup_single_server(ssl_enabled = true)
      ensure_setup
      # Create SSL certificates if needed
      setup_ssl_certs if ssl_enabled

      # Configure server
      ConfigBuilder.build("test_server1") do |config|
        config.port(16667)
        config.ssl_enabled(ssl_enabled)
        config.ssl_port(16697)
        config.ssl_cert("spec/fixtures/ssl/server1/server.crt", "spec/fixtures/ssl/server1/server.key") if ssl_enabled
      end

      server = TestServer.new("test_server1", 16667, 16697)
      servers << server
      server.start
    end

    def setup_linked_servers(ssl_enabled = true)
      ensure_setup
      # Create SSL certificates if needed
      setup_ssl_certs if ssl_enabled

      # Configure Server 1
      ConfigBuilder.build("test_server1") do |config|
        config.port(16667)
        config.ssl_enabled(ssl_enabled)
        config.ssl_port(16697)
        config.ssl_cert("spec/fixtures/ssl/server1/server.crt", "spec/fixtures/ssl/server1/server.key") if ssl_enabled
        config.add_linked_server("localhost", 17697, ssl_enabled)
      end

      # Configure Server 2
      ConfigBuilder.build("test_server2") do |config|
        config.port(17667)
        config.ssl_enabled(ssl_enabled)
        config.ssl_port(17697)
        config.ssl_cert("spec/fixtures/ssl/server2/server.crt", "spec/fixtures/ssl/server2/server.key") if ssl_enabled
        config.add_linked_server("localhost", 16697, ssl_enabled)
      end

      # Start servers
      server1 = TestServer.new("test_server1", 16667, 16697)
      server2 = TestServer.new("test_server2", 17667, 17697)

      servers << server1 << server2

      server1.start
      server2.start

      # Wait for link establishment
      sleep 1.second
    end

    def create_client(nickname : String, port : Int32 = 16697, ssl : Bool = true) : TestClient
      client = TestClient.new(nickname, "localhost", port, ssl)
      clients << client
      client
    end

    def teardown
      clients.each(&.close)
      servers.each(&.stop)
      cleanup_fixtures
    end

    private def ensure_setup
      # Ensure directories exist
      Dir.mkdir_p("spec/fixtures")
      Dir.mkdir_p("spec/logs")

      # Kill any leftover processes
      system("pkill -f 'circed_test.*spec/fixtures' 2>/dev/null || true")
      sleep 0.5.seconds

      # Build server if needed
      unless File.exists?("./circed_test") && File.info("./circed_test").modification_time > File.info("src/circed.cr").modification_time
        puts "Building IRC server for integration tests..."
        result = system("crystal build src/circed.cr -o circed_test")
        raise "Failed to build server" unless result
      end
    end

    private def setup_ssl_certs
      return if File.exists?("spec/fixtures/ssl/server1/server.crt")

      puts "Generating SSL certificates for testing..."
      Dir.mkdir_p("spec/fixtures/ssl/server1")
      Dir.mkdir_p("spec/fixtures/ssl/server2")
      Dir.mkdir_p("spec/fixtures/ssl/ca")

      # Generate test certificates (simplified)
      system(%(
        cd spec/fixtures/ssl &&
        openssl genrsa -out ca/ca.key 2048 2>/dev/null &&
        openssl req -new -x509 -days 365 -key ca/ca.key -out ca/ca.crt \
          -subj "/C=US/ST=Test/L=Test/O=Test/CN=TestCA" 2>/dev/null &&

        for i in 1 2; do
          openssl genrsa -out server$i/server.key 2048 2>/dev/null &&
          openssl req -new -key server$i/server.key -out server$i/server.csr \
            -subj "/C=US/ST=Test/L=Test/O=Test/CN=server$i.test" 2>/dev/null &&
          openssl x509 -req -days 365 -in server$i/server.csr \
            -CA ca/ca.crt -CAkey ca/ca.key -CAcreateserial \
            -out server$i/server.crt 2>/dev/null &&
          rm server$i/server.csr
        done
      ))
    end

    private def cleanup_fixtures
      # Clean up test files but preserve structure for next run
      Dir["spec/fixtures/*.yml"].each { |file| File.delete(file) rescue nil }
      Dir["spec/logs/*.log"].each { |file| File.delete(file) rescue nil }
    end
  end

  # Global test setup and cleanup hooks
  Spec.before_suite do
    # Ensure clean state before any integration tests
    system("pkill -f 'circed_test.*spec/fixtures' 2>/dev/null || true")
    sleep 1.second
  end

  Spec.after_suite do
    # Final cleanup after all tests
    system("pkill -f 'circed_test.*spec/fixtures' 2>/dev/null || true")
    Dir["spec/fixtures/*.yml"].each { |file| File.delete(file) rescue nil }
    Dir["spec/logs/*.log"].each { |file| File.delete(file) rescue nil }
  end
end

# Make helpers available in specs
include IntegrationHelper
include IntegrationHelper::Assertions
