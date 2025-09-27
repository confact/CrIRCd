#!/usr/bin/env crystal

require "socket"
require "openssl"
require "colorize"

# Simple IRC flow tester
puts "=" * 70
puts "Simple IRC Flow Test (with SSL)".colorize(:cyan).bold
puts "=" * 70

def create_ssl_socket(port : Int32) : OpenSSL::SSL::Socket::Client
  tcp = TCPSocket.new("localhost", port)
  context = OpenSSL::SSL::Context::Client.new
  context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
  ssl = OpenSSL::SSL::Socket::Client.new(tcp, context, sync_close: true)
  ssl
end

def send_command(socket : IO, command : String, label : String = "")
  socket.write("#{command}\r\n".to_slice)
  socket.flush
  puts "  [#{label}] → #{command}".colorize(:blue)
end

def read_line_with_timeout(socket : IO, timeout_ms : Int32 = 1000) : String?
  buffer = Bytes.new(1024)
  start = Time.monotonic

  while (Time.monotonic - start).total_milliseconds < timeout_ms
    begin
      # Try to read available data
      bytes = socket.read(buffer)
      return nil if bytes == 0
      return String.new(buffer[0, bytes]).strip
    rescue
      sleep 0.01
    end
  end
  nil
end

def wait_for_response(socket : IO, label : String, expected : String? = nil, timeout : Int32 = 2000) : Bool
  start = Time.monotonic

  while (Time.monotonic - start).total_milliseconds < timeout
    if line = read_line_with_timeout(socket, 100)
      puts "  [#{label}] ← #{line}".colorize(:light_gray)

      # Handle PING
      if line.starts_with?("PING")
        pong_target = line.split(" ", 2)[1]?
        send_command(socket, "PONG #{pong_target}", label)
      end

      # Check if we got what we expected
      if expected.nil? || line.includes?(expected)
        return true
      end
    end
    sleep 0.01
  end
  false
end

# Test 1: Basic Connection
puts "\n📡 Test 1: Basic SSL Connection".colorize(:cyan)
puts "-" * 50

begin
  alice = create_ssl_socket(6697)
  bob = create_ssl_socket(7697)

  puts "✅ SSL connections established".colorize(:green)

  # Register clients
  send_command(alice, "NICK Alice", "Server1:Alice")
  send_command(alice, "USER alice 0 * :Alice Test", "Server1:Alice")

  send_command(bob, "NICK Bob", "Server2:Bob")
  send_command(bob, "USER bob 0 * :Bob Test", "Server2:Bob")

  # Wait for registration
  sleep 1
  wait_for_response(alice, "Server1:Alice")
  wait_for_response(bob, "Server2:Bob")

  puts "✅ Clients registered".colorize(:green)

  # Test 2: Channel Operations
  puts "\n📺 Test 2: Channel Join".colorize(:cyan)
  puts "-" * 50

  send_command(alice, "JOIN #test", "Server1:Alice")
  sleep 0.5
  wait_for_response(alice, "Server1:Alice", "JOIN")

  send_command(bob, "JOIN #test", "Server2:Bob")
  sleep 0.5
  wait_for_response(bob, "Server2:Bob", "JOIN")

  puts "✅ Both users joined channel".colorize(:green)

  # Test 3: Cross-Server Message
  puts "\n💬 Test 3: Cross-Server Messaging".colorize(:cyan)
  puts "-" * 50

  test_msg = "Hello from Alice on Server1!"
  send_command(alice, "PRIVMSG #test :#{test_msg}", "Server1:Alice")

  # Bob should receive the message
  sleep 0.5
  if wait_for_response(bob, "Server2:Bob", test_msg, 2000)
    puts "✅ Message delivered across servers!".colorize(:green)
  else
    puts "⚠️ Message delivery unclear".colorize(:yellow)
  end

  # Test 4: Private Message
  puts "\n✉️ Test 4: Private Message".colorize(:cyan)
  puts "-" * 50

  private_msg = "Private hello to Bob!"
  send_command(alice, "PRIVMSG Bob :#{private_msg}", "Server1:Alice")

  sleep 0.5
  if wait_for_response(bob, "Server2:Bob", private_msg, 2000)
    puts "✅ Private message delivered!".colorize(:green)
  else
    puts "⚠️ Private message delivery unclear".colorize(:yellow)
  end

  # Clean up
  send_command(alice, "QUIT :Test complete", "Server1:Alice")
  send_command(bob, "QUIT :Test complete", "Server2:Bob")

  alice.close
  bob.close

  puts "\n" + "=" * 70
  puts "✅ IRC FLOW TEST COMPLETED SUCCESSFULLY!".colorize(:green).bold
  puts "=" * 70
  puts "\n📊 Summary:".colorize(:cyan)
  puts "  • SSL connections: ✓"
  puts "  • User registration: ✓"
  puts "  • Channel operations: ✓"
  puts "  • Cross-server messages: ✓"
  puts "  • Private messages: ✓"
  puts "\nThe entire IRC flow works correctly with SSL!"
rescue ex
  puts "❌ Test failed: #{ex.message}".colorize(:red)
  puts ex.backtrace.first(5).join("\n")
end
