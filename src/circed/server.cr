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

      # Accept connections from both plain and SSL servers
      spawn accept_loop(server, false)

      if ssl_server = @@ssl_server
        spawn accept_loop(ssl_server, true)
      end

      sleep
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
                               ssl_socket = Network::SSLSocket.wrap_server_socket(connection, ctx)
                               Log.info { "SSL handshake completed with #{remote_addr}" }
                               if peer_info = Network::SSLSocket.get_peer_info(ssl_socket)
                                 Log.info { "SSL peer info: #{peer_info}" }
                               end
                               ssl_socket
                             rescue ex
                               Log.error { "SSL handshake failed: #{ex.message}" }
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
      start_time = Time.utc
      timeout = 10.seconds # 10 second timeout

      # Read all available commands with a small delay to allow for multiple commands
      loop do
        # Check for timeout
        if Time.utc - start_time > timeout
          Log.warn { "Connection type determination timed out" }
          return nil
        end

        # Try to read a command
        message = connection.gets.try(&.strip)
        break unless message

        buffer << message
        Log.debug { "Read command: #{message}" }

        # Check if we have enough information to determine type
        connection_type = detect_connection_type(buffer)
        if connection_type
          Log.debug { "Connection type determined: #{connection_type}" }
          return connection_type
        end

        # If we don't have enough info yet, wait a bit for more commands
        # This allows for commands that might be sent with small delays
        sleep(0.1.seconds)
      end

      # If we've read some commands but couldn't determine type,
      # assume it's a client if we have any client-like commands
      if buffer.any? { |cmd| cmd.upcase.starts_with?("NICK") || cmd.upcase.starts_with?("USER") }
        Log.debug { "Assuming client connection based on partial commands" }
        return :client
      end

      Log.warn { "Could not determine connection type, buffer: #{buffer}" }
      nil
    end

    def self.detect_connection_type(buffer) : Symbol?
      commands = extract_commands(buffer)

      if commands.includes?("PASS") && commands.includes?("SERVER")
        :server
      elsif commands.includes?("NICK") || commands.includes?("USER") || commands.includes?("CAP")
        # If we see NICK, USER, or CAP, it's likely a client
        # We'll let the client handling deal with missing commands
        :client
      else
        nil
      end
    end

    def self.extract_commands(buffer) : Set(String)
      buffer.map(&.split(' ', 2).first.upcase).to_set
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
        spawn do
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
            Log.info { "Successfully connected to server: #{linked_server.host}" }
          rescue ex
            Log.error { "Failed to connect to server #{linked_server.host}:#{linked_server.port} - #{ex.message}" }
            # Could implement retry logic here
          end
        end
      end
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
      ":" + config.host
    end

    def self.name
      config.host
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
