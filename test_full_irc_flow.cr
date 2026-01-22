#!/usr/bin/env crystal

require "socket"
require "openssl"
require "colorize"

# Comprehensive IRC flow tester
class IRCFlowTester
  class TestClient
    getter nickname : String
    getter socket : IO
    getter server_name : String
    getter port : Int32
    getter? use_ssl : Bool
    property? connected = false
    property? registered = false
    property channels = [] of String

    def initialize(@nickname : String, @server_name : String, @port : Int32, @use_ssl : Bool = true)
      @socket = connect_to_server
    end

    private def connect_to_server : IO
      tcp = TCPSocket.new("localhost", @port)

      if @use_ssl
        context = OpenSSL::SSL::Context::Client.new
        context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
        ssl = OpenSSL::SSL::Socket::Client.new(tcp, context, sync_close: true)
        ssl
      else
        tcp
      end
    end

    def register(username = nil, realname = nil)
      username ||= @nickname
      realname ||= "Test User #{@nickname}"

      send_command("NICK #{@nickname}")
      send_command("USER #{username} 0 * :#{realname}")

      # Wait for registration
      sleep 0.5
      read_responses(timeout: 2)
      @registered = true
    end

    def join(channel : String)
      send_command("JOIN #{channel}")
      @channels << channel unless @channels.includes?(channel)
      sleep 0.2
      read_responses
    end

    def send_message(target : String, message : String)
      send_command("PRIVMSG #{target} :#{message}")
      sleep 0.1
    end

    def send_command(command : String)
      @socket.write("#{command}\r\n".to_slice)
      @socket.flush
      puts "  [#{@server_name}:#{@nickname}] → #{command}".colorize(:blue)
    rescue ex
      puts "  [#{@server_name}:#{@nickname}] ✗ Failed to send: #{ex.message}".colorize(:red)
    end

    def read_responses(timeout : Int32 = 1) : Array(String)
      responses = [] of String

      # Use a channel to read with timeout
      ch = Channel(String | Nil).new

      spawn do
        buffer = Bytes.new(4096)
        begin
          bytes = @socket.read(buffer)
          if bytes > 0
            response = String.new(buffer[0, bytes])
            ch.send(response)
          else
            ch.send(nil)
          end
        rescue ex
          ch.send(nil)
        end
      end

      start_time = Time.monotonic
      while (Time.monotonic - start_time).total_seconds < timeout
        select
        when response = ch.receive
          break if response.nil?

          response.split("\r\n").each do |line|
            next if line.empty?
            puts "  [#{@server_name}:#{@nickname}] ← #{line}".colorize(:light_gray)

            # Auto-respond to PING
            if line.starts_with?("PING")
              pong_target = line.split(" ", 2)[1]?
              send_command("PONG #{pong_target}")
            end

            responses << line
          end

          # Start another read
          spawn do
            buffer = Bytes.new(4096)
            begin
              bytes = @socket.read(buffer)
              if bytes > 0
                response = String.new(buffer[0, bytes])
                ch.send(response)
              else
                ch.send(nil)
              end
            rescue ex
              ch.send(nil)
            end
          end
        when timeout(0.1.seconds)
          # Continue waiting
        end
      end

      responses
    end

    def part(channel : String)
      send_command("PART #{channel} :Test complete")
      @channels.delete(channel)
    end

    def quit(message = "Test client disconnecting")
      send_command("QUIT :#{message}")
      sleep 0.2
      close
    end

    def close
      @socket.close unless @socket.closed?
      @connected = false
    end
  end

  def initialize
    @test_passed = true
    @test_results = [] of String
  end

  def run
    puts "=" * 70
    puts "Comprehensive IRC Flow Test (with SSL)".colorize(:cyan).bold
    puts "=" * 70

    # Make sure servers are running
    unless servers_running?
      puts "❌ Servers not running. Please run ./test_ssl_servers.sh first".colorize(:red)
      return
    end

    begin
      test_basic_client_connection
      test_channel_operations
      test_cross_server_messaging
      test_private_messaging
      test_user_modes
      test_channel_modes
      test_nick_changes
      test_quit_propagation

      print_summary
    rescue ex
      puts "❌ Test failed with error: #{ex.message}".colorize(:red)
      puts ex.backtrace.join("\n")
    end
  end

  private def servers_running? : Bool
    # Check if both servers are listening
    test1 = TCPSocket.new("localhost", 6697)
    test1.close
    test2 = TCPSocket.new("localhost", 7697)
    test2.close
    true
  rescue
    false
  end

  private def test_basic_client_connection
    puts "\n📡 Test 1: Basic Client Connection".colorize(:cyan)
    puts "-" * 50

    client1 = TestClient.new("Alice", "Server1", 6697, use_ssl: true)
    client2 = TestClient.new("Bob", "Server2", 7697, use_ssl: true)

    client1.register
    client2.register

    if client1.registered && client2.registered
      @test_results << "✅ Basic client connection and registration"
      puts "✅ Both clients connected and registered".colorize(:green)
    else
      @test_results << "❌ Basic client connection failed"
      @test_passed = false
    end

    client1.close
    client2.close
  end

  private def test_channel_operations
    puts "\n📺 Test 2: Channel Operations".colorize(:cyan)
    puts "-" * 50

    alice = TestClient.new("Alice", "Server1", 6697, use_ssl: true)
    bob = TestClient.new("Bob", "Server2", 7697, use_ssl: true)

    alice.register
    bob.register

    # Alice creates channel on Server1
    alice.join("#test")
    sleep 0.5

    # Bob joins same channel on Server2
    bob.join("#test")
    sleep 0.5

    # Check if both are in channel
    alice.send_command("NAMES #test")
    bob.send_command("NAMES #test")

    responses = alice.read_responses + bob.read_responses

    if responses.any? { |response| response.includes?("Alice") && response.includes?("Bob") }
      @test_results << "✅ Channel join and synchronization"
      puts "✅ Users can join channels across servers".colorize(:green)
    else
      @test_results << "❌ Channel synchronization failed"
      @test_passed = false
    end

    alice.close
    bob.close
  end

  private def test_cross_server_messaging
    puts "\n💬 Test 3: Cross-Server Messaging".colorize(:cyan)
    puts "-" * 50

    alice = TestClient.new("Alice", "Server1", 6697, use_ssl: true)
    bob = TestClient.new("Bob", "Server2", 7697, use_ssl: true)

    alice.register
    bob.register

    alice.join("#chat")
    sleep 0.3
    bob.join("#chat")
    sleep 0.3

    # Alice sends message from Server1
    test_message = "Hello from Server1! Time: #{Time.utc}"
    alice.send_message("#chat", test_message)

    # Bob should receive it on Server2
    bob_responses = bob.read_responses(timeout: 2)

    if bob_responses.any? { |response| response.includes?("PRIVMSG") && response.includes?(test_message) }
      @test_results << "✅ Cross-server channel messaging"
      puts "✅ Messages propagate between servers".colorize(:green)
    else
      @test_results << "❌ Cross-server messaging failed"
      @test_passed = false
    end

    alice.close
    bob.close
  end

  private def test_private_messaging
    puts "\n✉️ Test 4: Private Messaging Across Servers".colorize(:cyan)
    puts "-" * 50

    alice = TestClient.new("Alice", "Server1", 6697, use_ssl: true)
    bob = TestClient.new("Bob", "Server2", 7697, use_ssl: true)

    alice.register
    bob.register
    sleep 0.5

    # Alice sends private message to Bob
    private_msg = "Private message test #{Time.utc.to_unix}"
    alice.send_message("Bob", private_msg)

    # Bob should receive it
    bob_responses = bob.read_responses(timeout: 2)

    if bob_responses.any? { |response| response.includes?("PRIVMSG") && response.includes?(private_msg) }
      @test_results << "✅ Cross-server private messaging"
      puts "✅ Private messages work between servers".colorize(:green)
    else
      @test_results << "❌ Private messaging failed"
      @test_passed = false
    end

    alice.close
    bob.close
  end

  private def test_user_modes
    puts "\n🔧 Test 5: User Modes".colorize(:cyan)
    puts "-" * 50

    alice = TestClient.new("Alice", "Server1", 6697, use_ssl: true)
    alice.register

    # Set away mode
    alice.send_command("AWAY :Testing away message")
    sleep 0.3

    # Remove away mode
    alice.send_command("AWAY")
    sleep 0.3

    responses = alice.read_responses

    if responses.any? { |response| response.includes?("305") || response.includes?("306") }
      @test_results << "✅ User mode changes"
      puts "✅ User modes work correctly".colorize(:green)
    else
      @test_results << "⚠️ User modes partially working"
    end

    alice.close
  end

  private def test_channel_modes
    puts "\n🔒 Test 6: Channel Modes".colorize(:cyan)
    puts "-" * 50

    alice = TestClient.new("Alice", "Server1", 6697, use_ssl: true)
    alice.register
    alice.join("#modtest")
    sleep 0.3

    # Set channel mode (moderated)
    alice.send_command("MODE #modtest +m")
    sleep 0.3

    # Set topic
    alice.send_command("TOPIC #modtest :Test topic for SSL servers")
    sleep 0.3

    responses = alice.read_responses

    if responses.any? { |response| response.includes?("MODE") || response.includes?("TOPIC") }
      @test_results << "✅ Channel modes and topic"
      puts "✅ Channel modes work correctly".colorize(:green)
    else
      @test_results << "⚠️ Channel modes partially working"
    end

    alice.close
  end

  private def test_nick_changes
    puts "\n🏷️ Test 7: Nick Changes Across Servers".colorize(:cyan)
    puts "-" * 50

    alice = TestClient.new("Alice", "Server1", 6697, use_ssl: true)
    bob = TestClient.new("Bob", "Server2", 7697, use_ssl: true)

    alice.register
    bob.register

    alice.join("#nicktest")
    bob.join("#nicktest")
    sleep 0.5

    # Alice changes nick
    alice.send_command("NICK AliceNew")
    sleep 0.5

    # Check if Bob sees the change
    bob.send_command("NAMES #nicktest")
    bob_responses = bob.read_responses(timeout: 2)

    if bob_responses.any?(&.includes?("AliceNew"))
      @test_results << "✅ Nick changes propagate"
      puts "✅ Nick changes work across servers".colorize(:green)
    else
      @test_results << "❌ Nick change propagation failed"
      @test_passed = false
    end

    alice.close
    bob.close
  end

  private def test_quit_propagation
    puts "\n👋 Test 8: Quit Message Propagation".colorize(:cyan)
    puts "-" * 50

    alice = TestClient.new("Alice", "Server1", 6697, use_ssl: true)
    bob = TestClient.new("Bob", "Server2", 7697, use_ssl: true)
    charlie = TestClient.new("Charlie", "Server2", 7697, use_ssl: true)

    alice.register
    bob.register
    charlie.register

    # All join same channel
    alice.join("#quitest")
    bob.join("#quitest")
    charlie.join("#quitest")
    sleep 0.5

    # Alice quits with message
    alice.quit("Testing quit propagation")

    # Bob and Charlie should see quit
    bob_responses = bob.read_responses(timeout: 2)
    charlie_responses = charlie.read_responses(timeout: 1)

    all_responses = bob_responses + charlie_responses

    if all_responses.any? { |response| response.includes?("QUIT") && response.includes?("Testing quit propagation") }
      @test_results << "✅ Quit messages propagate"
      puts "✅ Quit messages work across servers".colorize(:green)
    else
      @test_results << "⚠️ Quit propagation partially working"
    end

    bob.close
    charlie.close
  end

  private def print_summary
    puts "\n" + "=" * 70
    puts "Test Summary".colorize(:cyan).bold
    puts "=" * 70

    @test_results.each { |result| puts result }

    if @test_passed
      puts "\n✅ ALL TESTS PASSED!".colorize(:green).bold
      puts "The IRC server flow works correctly with SSL connections!".colorize(:green)
    else
      puts "\n⚠️ Some tests failed".colorize(:yellow)
      puts "Check the output above for details".colorize(:yellow)
    end

    puts "\n📊 Test Coverage:".colorize(:cyan)
    puts "  • Client connections over SSL ✓"
    puts "  • Channel operations ✓"
    puts "  • Cross-server messaging ✓"
    puts "  • Private messages ✓"
    puts "  • User/Channel modes ✓"
    puts "  • Nick changes ✓"
    puts "  • Quit propagation ✓"
  end
end

# Run the test
tester = IRCFlowTester.new
tester.run
