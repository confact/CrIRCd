require "socket"
require "openssl"
require "yaml"
require "watcher"
require "./network/ssl_socket"

module Circed
  class ClosedClient < Exception; end

  class Server
    @@config_file : String = ARGV[0]? || "config.yml"
    class_getter config = Config.from_yaml(File.read(@@config_file))
    @@config_cache : String = File.read(@@config_file)
    @@start_time : Time = Time.utc
    @@container_initialized : Bool = false
    @@ssl_context : OpenSSL::SSL::Context::Server? = nil
    @@ssl_server : TCPServer? = nil
    INITIAL_LINK_RETRY_DELAY = 1.second
    MAX_LINK_RETRY_DELAY     = 30.seconds
    CLIENT_COMMANDS          = {
      "NICK", "USER", "CAP", "JOIN", "PART", "MODE", "KICK",
      "TOPIC", "INVITE", "LIST", "WHOIS", "WHO", "NAMES", "AWAY",
      "STARTTLS", "QUIT", "NOTICE", "PRIVMSG",
    }

    def self.start_time
      @@start_time
    end

    # @@servers

    def self.start
      initialize_container
      config.validate_ssl!
      watch_config_file

      # Start plain TCP server
      server = TCPServer.new(config.host, config.port)

      # Start SSL server if configured
      if ssl_config = config.ssl
        if ssl_config.enabled?
          setup_ssl_server
        end
      end

      start_message
      bootup_servers # Connect to configured servers
      start_client_heartbeat
      setup_signal_handlers(server)

      # Accept connections from both plain and SSL servers
      spawn accept_loop(server, false)

      if ssl_server = @@ssl_server
        spawn accept_loop(ssl_server, true)
      end

      sleep
    end

    private def self.setup_signal_handlers(server : TCPServer)
      shutdown = -> {
        Log.info { "Shutting down server #{name}" }
        ServerHandler.servers.each(&.close("Server shutting down"))
        server.close unless server.closed?
        if ssl_server = @@ssl_server
          ssl_server.close unless ssl_server.closed?
        end
        exit(0)
      }

      Signal::TERM.trap { shutdown.call }
      Signal::INT.trap { shutdown.call }
    end

    private def self.start_client_heartbeat
      spawn do
        loop do
          sleep 20.seconds
          now = Time.utc
          user_repository = Infrastructure::ServiceLocator.user_repository

          user_repository.each_client do |client|
            if client.heartbeat_timed_out?(now)
              Log.debug { "PONG timed out for #{client.nickname} - closing socket" }
              client.shutdown
            else
              client.send_heartbeat_ping(now)
            end
          end
        end
      end
    end

    private def self.accept_loop(server : TCPServer, is_ssl : Bool)
      loop do
        if client = server.accept?
          Log.info { "New #{is_ssl ? "SSL" : "plain"} connection from #{client.remote_address}" }
          spawn handle_client(client, is_ssl)
        else
          break
        end
      end
    end

    private def self.setup_ssl_server
      ssl_config = config.ssl
      return unless ssl_config && ssl_config.enabled?

      @@ssl_context = Network::SSLSocket.create_context(ssl_config)
      @@ssl_server = TCPServer.new(config.host, ssl_config.port)
      Log.info { "SSL server listening on #{config.host}:#{ssl_config.port}" }
    rescue ex
      Log.error { "Failed to setup SSL server: #{ex.message}" }
      @@ssl_server = nil
    end

    def self.handle_client(connection : TCPSocket, is_ssl : Bool = false)
      # Store remote address before SSL wrapping (which might not expose it)
      remote_addr = connection.remote_address

      # Wrap with SSL if needed
      wrapped_connection = if is_ssl && (ctx = @@ssl_context)
                             begin
                               # Set a timeout for SSL handshake
                               connection.read_timeout = 10.seconds
                               connection.write_timeout = 10.seconds

                               ssl_socket = Network::SSLSocket.wrap_server_socket(connection, ctx)

                               # Verify handshake completed successfully
                               if peer_info = Network::SSLSocket.get_peer_info(ssl_socket)
                                 Log.info { "SSL handshake completed with #{remote_addr} (#{peer_info})" }
                               else
                                 Log.info { "SSL handshake completed with #{remote_addr}" }
                               end

                               ssl_socket
                             rescue ex : OpenSSL::SSL::Error
                               Log.error { "SSL handshake failed with #{remote_addr}: #{ex.message}" }
                               connection.close
                               return
                             rescue ex : IO::TimeoutError
                               Log.error { "SSL handshake timed out with #{remote_addr}" }
                               connection.close
                               return
                             rescue ex
                               Log.error { "SSL connection failed with #{remote_addr}: #{ex.message}" }
                               connection.close
                               return
                             end
                           else
                             connection
                           end

      handle_wrapped_client(wrapped_connection, remote_addr)
    end

    def self.handle_wrapped_client(connection : Network::SSLSocket::IRCSocket, remote_addr : Socket::IPAddress)
      buffer = [] of String

      type = determine_connection_type(connection, buffer)

      case type
      when :server
        handle_server_connection(connection, buffer, remote_addr)
      when :client
        handle_user_connection(connection, buffer)
      else
        Log.warn { "Unknown connection type from #{remote_addr}" }
        connection.close
      end
    end

    private def self.determine_connection_type(connection : Network::SSLSocket::IRCSocket, buffer)
      if connection.is_a?(TCPSocket)
        connection.read_timeout = 10.seconds
      end

      begin
        loop do
          line = connection.gets
          break unless line
          message = line.chomp

          buffer << message
          Log.debug { "Read command: #{message}" }

          # Check if we have enough information to determine type
          connection_type = detect_connection_type(buffer)
          if connection_type
            Log.debug { "Connection type determined: #{connection_type}" }
            return connection_type
          end
        end

        # If we've read any commands but couldn't determine type, assume client.
        # Client command processing will handle registration checks and errors.
        if !buffer.empty?
          Log.debug { "Defaulting to client connection (no PASS/SERVER detected)" }
          return :client
        end

        Log.warn { "Could not determine connection type, buffer: #{buffer}" }
        nil
      rescue IO::TimeoutError
        Log.warn { "Connection type determination timed out" }
        nil
      ensure
        if connection.is_a?(TCPSocket)
          connection.read_timeout = nil
        end
      end
    end

    def self.detect_connection_type(buffer) : Symbol?
      saw_pass = false
      saw_server = false
      saw_client_command = false

      buffer.each do |line|
        command_length = command_length(line)
        saw_pass = true if command_equals?(line, command_length, "PASS")
        saw_server = true if command_equals?(line, command_length, "SERVER")
        saw_client_command = true if client_command?(line, command_length)
      end

      return :server if saw_pass && saw_server
      return :client if saw_client_command

      nil
    end

    private def self.client_command?(line : String, command_length : Int32) : Bool
      CLIENT_COMMANDS.any? do |command|
        command_equals?(line, command_length, command)
      end
    end

    private def self.command_length(line : String) : Int32
      line.index(' ') || line.bytesize
    end

    private def self.command_equals?(line : String, command_length : Int32, expected : String) : Bool
      return false unless command_length == expected.bytesize

      index = 0
      while index < command_length
        return false unless ascii_upcase(line.byte_at(index)) == expected.byte_at(index)

        index += 1
      end

      true
    end

    private def self.ascii_upcase(byte : UInt8) : UInt8
      value = byte.to_i
      if value >= 97 && value <= 122
        (value - 32).to_u8
      else
        byte
      end
    end

    private def self.client_command?(command : String) : Bool
      case command
      when "NICK", "USER", "CAP", "JOIN", "PART", "MODE", "KICK",
           "TOPIC", "INVITE", "LIST", "WHOIS", "WHO", "NAMES", "AWAY",
           "STARTTLS", "QUIT", "NOTICE", "PRIVMSG"
        true
      else
        false
      end
    end

    def self.extract_commands(buffer) : Set(String)
      buffer.map { |line| extract_command(line) }.to_set
    end

    private def self.extract_command(line : String) : String
      if index = line.index(' ')
        line[0, index].upcase
      else
        line.upcase
      end
    end

    def self.handle_user_connection(client : Network::SSLSocket::IRCSocket, buffer)
      user_repo = Infrastructure::ServiceLocator.user_repository

      # Get remote address for logging
      remote_addr_str = case client
                        when TCPSocket
                          client.remote_address.to_s
                        else
                          "unknown"
                        end

      if user_repo.count >= config.max_users
        Log.warn { "User limit reached, refusing new client: #{remote_addr_str}" }
        client.puts "ERROR :Closing Link: #{remote_addr_str} (Max users limit reached)"
        sleep 1.second
        client.close
        return
      end

      new_client = Circed::Client.new(client, buffer)
      Log.debug { "new client: #{new_client.inspect}" }
      new_client.setup
      # new_client.send_message(motd)
    end

    def self.handle_server_connection(connection : Network::SSLSocket::IRCSocket, buffer, remote_addr : Socket::IPAddress)
      server = Circed::LinkServer.new(connection, buffer, remote_addr)
      Log.debug { "new server connected: #{server.name} from #{server.host}" }
    rescue ex
      Log.error { "Failed to establish server connection: #{ex.message}" }
      connection.close
    end

    def self.bootup_servers
      config.linked_servers.each do |linked_server|
        spawn supervise_link(linked_server)
      end
    end

    private def self.supervise_link(linked_server : LinkedServer)
      retry_delay = INITIAL_LINK_RETRY_DELAY

      loop do
        if configured_link_connected?(linked_server)
          retry_delay = INITIAL_LINK_RETRY_DELAY
          sleep MAX_LINK_RETRY_DELAY
          next
        end

        begin
          Log.info { "Attempting to connect to server: #{linked_server.host}:#{linked_server.port} (SSL: #{linked_server.use_ssl?})" }
          Circed::LinkServer.new(
            linked_server.host,
            linked_server.host,
            linked_server.port,
            linked_server.link_password,
            linked_server.use_ssl?,
            linked_server.verify_ssl?
          )
          Log.info { "Server link to #{linked_server.host}:#{linked_server.port} disconnected; retrying" }
          retry_delay = INITIAL_LINK_RETRY_DELAY
        rescue ex
          Log.error { "Failed to connect to server #{linked_server.host}:#{linked_server.port} - #{ex.message}; retrying in #{retry_delay}" }
          sleep retry_delay
          retry_delay = next_link_retry_delay(retry_delay)
        end
      end
    end

    private def self.configured_link_connected?(linked_server : LinkedServer) : Bool
      servers = ServerHandler.servers
      return !servers.empty? if config.linked_servers.size == 1

      servers.any? do |server|
        server.target_host == linked_server.host && server.target_port == linked_server.port ||
          server.name == linked_server.host
      end
    end

    private def self.next_link_retry_delay(current_delay : Time::Span) : Time::Span
      next_delay = current_delay * 2
      next_delay > MAX_LINK_RETRY_DELAY ? MAX_LINK_RETRY_DELAY : next_delay
    end

    def self.created
      @@config.created
    end

    def self.welcome_message(client : Client)
      client.send_message(Server.clean_name, Numerics::RPL_WELCOME, client.nickname, ":Welcome to the #{Server.config.network} IRC Network, #{client.nickname}!")
      client.send_message(Server.clean_name, Numerics::RPL_YOURHOST, client.nickname, ":Your host is #{Server.config.host}, running version #{VERSION}")
      client.send_message(Server.clean_name, Numerics::RPL_CREATED, client.nickname, ":This server was created on #{Server.start_time}")
      client.send_message(Server.clean_name, Numerics::RPL_MYINFO, client.nickname, "#{Server.config.host} #{VERSION} oiwszcrkfydnxbauglZCD biklmnopstvrDdRcC bkloveqjfI")

      # Sync new user with network state
      irc_service = Infrastructure::ServiceLocator.irc_service
      irc_service.sync_new_user(client)
    end

    def self.lusers(client : Client)
      nick = client.nickname
      user_repo = Infrastructure::ServiceLocator.user_repository
      channel_repo = Infrastructure::ServiceLocator.channel_repository

      data = ""
      data += Format.format_server_message(name, Numerics::RPL_LUSERCLIENT, nick, ":There are #{user_repo.count} users and 0 invisible on 1 server(s)")
      data += Format.format_server_message(name, Numerics::RPL_LUSEROP, nick, ":1 IRC Operators online")
      data += Format.format_server_message(name, Numerics::RPL_LUSERUNKNOWN, nick, ":0 unregistered connections")
      data += Format.format_server_message(name, Numerics::RPL_LUSERCHANNELS, nick, ":#{channel_repo.count} channels formed")
      data += Format.format_server_message(name, Numerics::RPL_LUSERME, nick, ":I have #{user_repo.count} clients and 1 servers")
      data += Format.format_server_message(name, Numerics::RPL_LOCALUSERS, nick, user_repo.count, config.max_users, ":Current local users #{user_repo.count}, max #{config.max_users}")
      data += Format.format_server_message(name, Numerics::RPL_GLOBALUSERS, nick, user_repo.count, config.max_users, ":Current global users #{user_repo.count}, max #{config.max_users}")
      data
    end

    def self.start_message
      puts " Circed #{VERSION}"
      puts " Running on #{config.host}:#{config.port}"
      if ssl_config = config.ssl
        if ssl_config.enabled?
          puts " SSL enabled on #{config.host}:#{ssl_config.port}"
        end
      end
      puts " ---"
    end

    def self.address
      ":" + config.host
    end

    def self.motd(client : Client)
      text = <<-TEXT
        Welcome to Circd Server
      TEXT
      motd = text.split("\n")
      data = ""
      data += Format.format_server_message(name, Numerics::RPL_MOTDSTART, client.nickname, ":- localhost Message of the day - ")
      motd.each do |line|
        data += Format.format_server_message(name, Numerics::RPL_MOTD, client.nickname, line)
      end
      data += Format.format_server_message(name, Numerics::RPL_ENDOFMOTD, client.nickname, "End of MOTD command")
      data
    end

    def self.clean_name
      ":" + name
    end

    def self.name
      config.server_name || config.host
    end

    def self.watch_config_file
      spawn do
        watch @@config_file, 2 do |event|
          event.on_change do
            file_content = File.read(@@config_file)
            if @@config_cache != file_content
              Log.info { "#{@@config_file} changed, reloading" }
              @@config_cache = file_content
              @@config = Config.from_yaml(file_content)
            end
          end
        end
      end
    end

    private def self.initialize_container
      return if @@container_initialized
      Infrastructure::Container.setup_default_services(config)
      @@container_initialized = true
      Log.info { "Dependency injection container initialized" }
    end
  end
end
