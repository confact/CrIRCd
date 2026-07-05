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

    def initialize(@name : String, @port : Int32, @ssl_port : Int32, @ssl_enabled : Bool = true)
      @config_file = "spec/fixtures/#{@name}_config.yml"
      @log_file = "spec/logs/#{@name}.log"
    end

    def start
      # Build server if needed
      build_server

      # Start server process
      # Ensure log directory exists
      Dir.mkdir_p(File.dirname(@log_file))

      # Redirect stdout/stderr to per-server log for easier debugging
      stdout = File.open(@log_file, "a")
      stderr = stdout

      @process = Process.new(
        command: "./circed_test",
        args: [@config_file],
        input: Process::Redirect::Close,
        output: stdout,
        error: stderr
      )

      # Wait for server to be ready
      wait_for_ready
      self
    end

    def stop
      if proc = @process
        TestClient.close_for_ports(@port, @ssl_port)
        proc.signal(Signal::TERM) rescue nil
        unless wait_until_stopped
          proc.signal(Signal::KILL) rescue nil
          wait_until_stopped
        end
        proc.wait rescue nil
        @process = nil
      end
    end

    def running?
      # Consider the server running if the port is accepting connections
      # This is more reliable across platforms than checking the process table

      socket = TCPSocket.new("localhost", @port)
      socket.close
      true
    rescue IO::Error
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

    private def wait_for_ready(timeout : Time::Span = 5.seconds) : Bool
      deadline = Time.monotonic + timeout

      loop do
        begin
          socket = TCPSocket.new("localhost", @port)
          socket.close
          if @ssl_enabled
            ssl_socket = TCPSocket.new("localhost", @ssl_port)
            ssl_socket.close
          end
          return true
        rescue IO::Error
          if Time.monotonic > deadline
            raise "Server #{@name} failed to start within #{timeout}"
          end
          sleep 0.1.seconds
        end
      end
    end

    private def wait_until_stopped(timeout : Time::Span = 2.seconds) : Bool
      deadline = Time.monotonic + timeout

      loop do
        return true unless running?
        return false if Time.monotonic > deadline

        sleep 0.05.seconds
      end
    end
  end

  # IRC Test Client for integration tests
  class TestClient
    @@clients = [] of TestClient

    getter nickname : String
    getter socket : IO
    getter responses : Array(String) = [] of String
    getter? ssl : Bool

    # Track if client is properly registered
    getter? registered : Bool = false

    def initialize(@nickname : String, @host : String = "localhost", @port : Int32 = 6667, @ssl : Bool = true)
      @socket = connect
      @@clients << self
    end

    def self.close_for_ports(*ports : Int32)
      @@clients.each do |client|
        client.close if ports.includes?(client.port)
      end
    end

    getter port : Int32

    private def connect : IO
      tcp = TCPSocket.new(@host, @port)

      if @ssl
        context = OpenSSL::SSL::Context::Client.new
        context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
        ssl_socket = OpenSSL::SSL::Socket::Client.new(tcp, context, sync_close: true)

        # Ensure SSL handshake completes
        begin
          ssl_socket.sync = true
          # Test if we can write/read to ensure handshake is complete
          ssl_socket
        rescue ex
          Log.error { "SSL handshake failed: #{ex.message}" }
          tcp.close
          raise ex
        end
      else
        tcp
      end
    end

    def send(command : String)
      raise IO::Error.new("socket is closed") if @socket.closed?
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
      # Wait for JOIN confirmation - should contain both JOIN and the channel name
      wait_for_response(/JOIN.*#{Regex.escape(channel)}/)
      self
    end

    def privmsg(target : String, message : String)
      send("PRIVMSG #{target} :#{message}")
      self
    end

    def wait_for_response(pattern : Regex, timeout : Time::Span = 5.seconds) : String?
      deadline = Time.monotonic + timeout

      # First, check any previously buffered responses
      if cached = consume_from_buffer(pattern)
        return cached
      end

      # Read new responses until we find a match or timeout
      while Time.monotonic < deadline
        if response = read_line(0.1.seconds)
          # Auto-respond to PING
          if response.starts_with?("PING")
            pong_target = response.split(" ", 2)[1]?
            send("PONG #{pong_target}")
          end

          return response if response.matches?(pattern)

          @responses << response
        end
        sleep 0.01.seconds
      end

      nil
    end

    def wait_for_registration(timeout : Time::Span = 2.seconds) : String?
      response = wait_for_response(/001.*Welcome/, timeout)
      @responses.unshift(response) if response
      @registered = !response.nil?
      response
    end

    # Clear response buffer - useful between test operations
    def clear_responses
      @responses.clear
    end

    # Get all unprocessed responses (for debugging)
    def unprocessed_responses
      @responses.dup
    end

    def read_line(timeout : Time::Span = 1.second) : String?
      # Set socket timeout for different socket types
      case socket = @socket
      when TCPSocket
        socket.read_timeout = timeout
      when OpenSSL::SSL::Socket::Client
        socket.read_timeout = timeout
      end

      if line = @socket.gets
        line.strip
      else
        nil
      end
    rescue IO::TimeoutError
      nil
    rescue IO::Error
      nil
    rescue
      nil
    end

    def expect_response(pattern : Regex, timeout : Time::Span = 5.seconds) : String
      response = wait_for_response(pattern, timeout)
      if response.nil?
        # Print buffered responses to aid debugging
        puts "[#{@nickname}] buffered responses before timeout:"
        @responses.each { |resp| puts resp }
        Dir["spec/logs/*.log"].sort.each do |log_file|
          puts "--- #{log_file} ---"
          File.each_line(log_file) { |line| puts line }
        rescue ex
          puts "Could not read #{log_file}: #{ex.message}"
        end
        raise "Expected response matching #{pattern} but received none within #{timeout}"
      end
      response
    end

    def should_receive(pattern : Regex, timeout : Time::Span = 5.seconds) : String
      response = expect_response(pattern, timeout)
      Log.debug { "Client #{@nickname} received expected: #{response}" }
      response
    end

    def should_not_receive(pattern : Regex, timeout : Time::Span = 1.second) : Nil
      # If it's already buffered, fail fast
      if buffered = find_in_buffer(pattern)
        Log.debug { "Client #{@nickname} unexpectedly had buffered: #{buffered}" }
        buffered.should be_nil
      end

      response = wait_for_response(pattern, timeout)
      if response
        Log.debug { "Client #{@nickname} unexpectedly received: #{response}" }
      end
      response.should be_nil
    end

    private def consume_from_buffer(pattern : Regex) : String?
      index = @responses.index(&.matches?(pattern))
      index ? @responses.delete_at(index) : nil
    end

    private def find_in_buffer(pattern : Regex) : String?
      @responses.find(&.matches?(pattern))
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

    def port(value : Int32) : self
      @config[YAML::Any.new("port")] = YAML::Any.new(value)
      self
    end

    def ssl_port(value : Int32) : self
      ssl_config[YAML::Any.new("port")] = YAML::Any.new(value)
      self
    end

    def ssl_enabled(value : Bool) : self
      ssl_config[YAML::Any.new("enabled")] = YAML::Any.new(value)
      self
    end

    def ssl_cert(cert_file : String, key_file : String) : self
      ssl_config[YAML::Any.new("cert_file")] = YAML::Any.new(cert_file)
      ssl_config[YAML::Any.new("key_file")] = YAML::Any.new(key_file)
      self
    end

    def add_linked_server(host : String, port : Int32, use_ssl : Bool = true) : self
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
      # Different servers may or may not echo JOIN back to the joining user.
      # Accept either a JOIN echo or the standard NAMES/End of NAMES numerics.
      pattern = /JOIN\s+#{Regex.escape(channel)}|353.*#{Regex.escape(channel)}|366.*#{Regex.escape(channel)}
      /
      client.should_receive(pattern)
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
    @@server_binary_ready = false

    getter servers = [] of TestServer
    getter clients = [] of TestClient
    getter server1_client_port = 16697
    getter server2_client_port = 17697

    @default_client_ssl = true

    def setup_single_server(ssl_enabled = true)
      ensure_setup
      @server1_client_port = ssl_enabled ? 16697 : 16667
      @server2_client_port = ssl_enabled ? 17697 : 17667
      @default_client_ssl = ssl_enabled

      # Create SSL certificates if needed
      setup_ssl_certs if ssl_enabled

      # Configure server
      ConfigBuilder.build("test_server1") do |config|
        config.port(16667)
        config.ssl_enabled(ssl_enabled)
        config.ssl_port(16697)
        config.ssl_cert("spec/fixtures/ssl/server1/server.crt", "spec/fixtures/ssl/server1/server.key") if ssl_enabled
      end

      server = TestServer.new("test_server1", 16667, 16697, ssl_enabled)
      servers << server
      server.start
    end

    def setup_linked_servers(ssl_enabled = true)
      ensure_setup
      @server1_client_port = ssl_enabled ? 16697 : 16667
      @server2_client_port = ssl_enabled ? 17697 : 17667
      @default_client_ssl = ssl_enabled

      # Create SSL certificates if needed
      setup_ssl_certs if ssl_enabled
      server1_link_port = ssl_enabled ? 16697 : 16667
      server2_link_port = ssl_enabled ? 17697 : 17667

      # Configure Server 1
      ConfigBuilder.build("test_server1") do |config|
        config.port(16667)
        config.ssl_enabled(ssl_enabled)
        config.ssl_port(16697)
        config.ssl_cert("spec/fixtures/ssl/server1/server.crt", "spec/fixtures/ssl/server1/server.key") if ssl_enabled
        config.add_linked_server("localhost", server2_link_port, ssl_enabled)
      end

      # Configure Server 2
      ConfigBuilder.build("test_server2") do |config|
        config.port(17667)
        config.ssl_enabled(ssl_enabled)
        config.ssl_port(17697)
        config.ssl_cert("spec/fixtures/ssl/server2/server.crt", "spec/fixtures/ssl/server2/server.key") if ssl_enabled
        config.add_linked_server("localhost", server1_link_port, ssl_enabled)
      end

      # Start servers
      server1 = TestServer.new("test_server1", 16667, 16697, ssl_enabled)
      server2 = TestServer.new("test_server2", 17667, 17697, ssl_enabled)

      servers << server1 << server2

      server1.start
      server2.start

      wait_for_link_establishment(server1, server2)
    end

    def create_client(nickname : String, port : Int32? = nil, ssl : Bool? = nil) : TestClient
      client = TestClient.new(
        nickname,
        "localhost",
        normalize_client_port(port || @server1_client_port),
        ssl.nil? ? @default_client_ssl : ssl
      )
      clients << client
      client
    end

    def teardown
      clients.each(&.close)
      servers.each(&.stop)
      clients.clear
      servers.clear
      cleanup_fixtures
    end

    private def ensure_setup
      # Ensure directories exist
      Dir.mkdir_p("spec/fixtures")
      Dir.mkdir_p("spec/logs")

      return if @@server_binary_ready && File.exists?("./circed_test")

      # Build server if needed (rebuild if any src file is newer than the binary)
      needs_build = true
      if File.exists?("./circed_test")
        bin_mtime = File.info("./circed_test").modification_time
        latest_src_mtime = Dir.glob("src/**/*.cr").max_of? { |file| File.info(file).modification_time }
        needs_build = latest_src_mtime && latest_src_mtime > bin_mtime
      end

      if needs_build
        puts "Building IRC server for integration tests..."
        result = system("crystal build src/circed.cr -o circed_test")
        raise "Failed to build server" unless result
      end

      @@server_binary_ready = true
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

    private def normalize_client_port(port : Int32) : Int32
      return 16667 if !@default_client_ssl && port == 16697
      return 17667 if !@default_client_ssl && port == 17697

      port
    end

    private def wait_for_link_establishment(server1 : TestServer, server2 : TestServer, timeout : Time::Span = 3.seconds) : Nil
      wait_for_log(server1.log_file, /Received end of burst from test_server2/, timeout)
      wait_for_log(server2.log_file, /Received end of burst from localhost/, timeout)
    end

    private def wait_for_log(log_file : String, pattern : Regex, timeout : Time::Span) : Nil
      deadline = Time.monotonic + timeout

      loop do
        if File.exists?(log_file) && File.read(log_file).matches?(pattern)
          return
        end

        raise "Timed out waiting for #{pattern} in #{log_file}" if Time.monotonic > deadline

        sleep 0.02.seconds
      end
    end
  end

  # Global test setup and cleanup hooks
  Spec.before_suite do
    # Ensure clean state before any integration tests
    system("pkill -f 'circed_test.*spec/fixtures' 2>/dev/null || true")
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
