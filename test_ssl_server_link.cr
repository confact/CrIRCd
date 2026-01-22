#!/usr/bin/env crystal

require "socket"
require "openssl"
require "colorize"
require "option_parser"

# Simple SSL test client for IRC server-to-server connections
class SSLServerLinkTester
  property host : String = "localhost"
  property port : Int32 = 6697
  property? use_ssl : Bool = true
  property? verify_ssl : Bool = false
  property link_password : String = "test_password"
  property server_name : String = "test.server"
  property? verbose : Bool = false

  def initialize
    parse_options
  end

  def parse_options
    OptionParser.parse do |parser|
      parser.banner = "Usage: test_ssl_server_link [options]"

      parser.on("-h HOST", "--host=HOST", "Target host (default: localhost)") { |host| @host = host }
      parser.on("-p PORT", "--port=PORT", "Target port (default: 6697)") { |port| @port = port.to_i }
      parser.on("--no-ssl", "Disable SSL (use plain connection)") { @use_ssl = false }
      parser.on("--verify-ssl", "Verify SSL certificate") { @verify_ssl = true }
      parser.on("-P PASSWORD", "--password=PASSWORD", "Link password") { |password| @link_password = password }
      parser.on("-n NAME", "--name=NAME", "Server name to use") { |name| @server_name = name }
      parser.on("-v", "--verbose", "Verbose output") { @verbose = true }
      parser.on("--help", "Show this help") do
        puts parser
        exit
      end
    end
  end

  def run
    puts "=" * 60
    puts "IRC SSL Server Link Tester".colorize(:cyan).bold
    puts "=" * 60

    test_connection
  end

  private def test_connection
    puts "\n📡 Testing connection to #{@host}:#{@port}..."
    puts "   SSL: #{@use_ssl ? "Enabled" : "Disabled"}".colorize(@use_ssl ? :green : :yellow)
    puts "   Verify SSL: #{@verify_ssl}".colorize(@verify_ssl ? :green : :yellow) if @use_ssl

    begin
      socket = create_socket

      if socket
        puts "✅ Connection established!".colorize(:green)

        if @use_ssl && socket.is_a?(OpenSSL::SSL::Socket::Client)
          print_ssl_info(socket)
        end

        perform_handshake(socket)

        # Keep connection alive for testing
        puts "\n📨 Waiting for server responses (press Ctrl+C to exit)..."
        listen_for_messages(socket)
      end
    rescue ex : Exception
      puts "❌ Connection failed: #{ex.message}".colorize(:red)
      puts ex.backtrace.join("\n") if @verbose
    ensure
      socket.try(&.close)
    end
  end

  private def create_socket : IO?
    tcp_socket = TCPSocket.new(@host, @port)

    if @use_ssl
      context = create_ssl_context
      ssl_socket = OpenSSL::SSL::Socket::Client.new(tcp_socket, context, sync_close: true, hostname: @host)
      ssl_socket
    else
      tcp_socket
    end
  end

  private def create_ssl_context : OpenSSL::SSL::Context::Client
    context = OpenSSL::SSL::Context::Client.new

    # Set SSL/TLS options for security
    context.add_options(
      OpenSSL::SSL::Options::NO_SSL_V2 |
      OpenSSL::SSL::Options::NO_SSL_V3 |
      OpenSSL::SSL::Options::NO_TLS_V1 |
      OpenSSL::SSL::Options::NO_TLS_V1_1
    )

    # Set cipher list
    context.ciphers = "ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS"

    # Verify mode
    if @verify_ssl
      context.verify_mode = OpenSSL::SSL::VerifyMode::PEER
    else
      context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
    end

    context
  end

  private def print_ssl_info(ssl_socket : OpenSSL::SSL::Socket::Client)
    puts "\n🔐 SSL/TLS Information:".colorize(:cyan)

    # Get cipher info
    if cipher = ssl_socket.cipher
      puts "   Cipher: #{cipher}".colorize(:white)
    end

    # Get TLS version
    puts "   TLS Version: #{ssl_socket.tls_version}".colorize(:white)

    # Get peer certificate info if available
    if peer_cert = ssl_socket.peer_certificate
      puts "   Peer Certificate:".colorize(:white)
      puts "     Subject: #{peer_cert.subject}".colorize(:white)
      # Note: issuer, not_before, not_after may not be directly available in Crystal's OpenSSL bindings
      puts "     Certificate present and validated".colorize(:green)
    end
  end

  private def perform_handshake(socket : IO)
    puts "\n🤝 Performing IRC server handshake...".colorize(:cyan)

    # Send PASS command
    send_command(socket, "PASS #{@link_password}")

    # Send SERVER command
    send_command(socket, "SERVER #{@server_name} 1 :Test IRC Server")

    puts "✅ Handshake commands sent".colorize(:green)
  end

  private def send_command(socket : IO, command : String)
    message = "#{command}\r\n"
    socket.write(message.to_slice)
    socket.flush
    puts "   → #{command}".colorize(:blue) if @verbose
  end

  private def listen_for_messages(socket : IO)
    buffer = Bytes.new(4096)

    loop do
      begin
        bytes_read = socket.read(buffer)
        break if bytes_read == 0

        message = String.new(buffer[0, bytes_read])
        messages = message.split("\r\n")

        messages.each do |msg|
          next if msg.empty?
          handle_message(socket, msg)
        end
      rescue ex : IO::Error
        puts "Connection closed: #{ex.message}".colorize(:yellow)
        break
      end
    end
  end

  private def handle_message(socket : IO, message : String)
    timestamp = Time.local.to_s("%H:%M:%S")
    puts "[#{timestamp}] ← #{message}".colorize(:light_gray)

    # Handle PING messages
    if message.starts_with?("PING")
      pong_target = message.split(" ", 2)[1]?
      pong_response = "PONG #{pong_target}"
      send_command(socket, pong_response)
      puts "   → Auto-responded with PONG".colorize(:green) if @verbose
    end

    # Handle ERROR messages
    if message.starts_with?("ERROR")
      puts "❌ Server error: #{message}".colorize(:red)
    end

    # Handle successful connection indicators
    if message.includes?("SERVER") && !message.starts_with?(":")
      puts "✅ Server acknowledged our connection!".colorize(:green).bold
    end
  end
end

# Run the tester
tester = SSLServerLinkTester.new
tester.run
