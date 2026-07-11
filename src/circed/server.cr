require "socket"
require "openssl"
require "yaml"
require "./network/ssl_socket"

module Circed
  class ClosedClient < Exception; end

  class Server
    @@config_file : String = ARGV[0]? || "config.yml"
    @@config_cache : String = File.read(@@config_file)
    class_getter config = Config.from_yaml(@@config_cache)
    @@start_time : Time = Time.utc
    @@container_initialized : Bool = false
    @@ssl_context : OpenSSL::SSL::Context::Server? = nil
    @@ssl_server : TCPServer? = nil
    INITIAL_LINK_RETRY_DELAY = 1.second
    MAX_LINK_RETRY_DELAY     = 30.seconds
    SUPPORTED_USER_MODES     = "iwoO"
    SUPPORTED_CHANNEL_MODES  = "biklmnopsthv"
    CLIENT_COMMANDS          = {
      "NICK", "USER", "CAP", "JOIN", "PART", "MODE", "KICK",
      "TOPIC", "INVITE", "LIST", "WHOIS", "WHO", "NAMES", "AWAY",
      "STARTTLS", "QUIT", "NOTICE", "PRIVMSG", "OPER", "KILL",
      "REHASH", "RESTART", "DIE", "CONNECT", "SQUIT", Domain::LineBan::KLINE,
      Domain::LineBan::GLINE, Domain::LineBan::ZLINE,
    }

    def self.start_time
      @@start_time
    end

    def self.config=(@@config : Config)
      Infrastructure::Container.setup_default_services(@@config)
      @@container_initialized = true
      configure_line_persistence
    end

    # @@servers

    def self.start
      initialize_container
      config.validate_ssl!
      configure_line_persistence
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
        handle_user_connection(connection, buffer, remote_addr)
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
          line = read_initial_line(connection)
          break unless line

          buffer << line
          Log.debug { "Read command: #{line}" }

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

    private def self.read_initial_line(connection : Network::SSLSocket::IRCSocket) : String?
      line = connection.gets('\n', Client::MAX_MESSAGE_BYTES + 1, chomp: false)
      return unless line

      if line.bytesize > Client::MAX_MESSAGE_BYTES
        connection << "#{clean_name} #{Numerics::ERR_INPUTTOOLONG} * :Input line was too long\r\n"
        connection.flush
        return
      end

      return unless line.ends_with?('\n')

      line.chomp
    end

    def self.detect_connection_type(buffer) : Symbol?
      pass = false
      server = false
      client = false
      each_command(buffer) do |command|
        pass = true if command == "PASS"
        server = true if command == "SERVER"
        client = true if CLIENT_COMMANDS.includes?(command)
      end

      return :server if pass && server
      return :client if client

      nil
    end

    def self.extract_commands(buffer) : Set(String)
      commands = Set(String).new
      each_command(buffer) { |command| commands << command }
      commands
    end

    private def self.each_command(buffer, & : String ->) : Nil
      buffer.each do |line|
        yield FastIRC.parse_line(line, strict: true).command.upcase
      rescue FastIRC::ParseException
        next
      end
    end

    def self.handle_user_connection(client : Network::SSLSocket::IRCSocket, buffer, remote_addr : Socket::IPAddress? = nil)
      user_repo = Infrastructure::ServiceLocator.user_repository

      # Get remote address for logging
      remote_addr_str = case client
                        when TCPSocket
                          client.remote_address.to_s
                        else
                          "unknown"
                        end

      if user_repo.size >= config.max_users
        Log.warn { "User limit reached, refusing new client: #{remote_addr_str}" }
        client.puts "ERROR :Closing Link: #{remote_addr_str} (Max users limit reached)"
        sleep 1.second
        client.close
        return
      end

      new_client = Circed::Client.new(client, buffer, remote_addr.try(&.address))
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
            linked_server.irc_name,
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
          server.name == linked_server.irc_name
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
      client.send_message(Server.clean_name, Numerics::RPL_MYINFO, client.nickname, Server.name, VERSION, SUPPORTED_USER_MODES, SUPPORTED_CHANNEL_MODES)
      client.send_message(Server.clean_name, Numerics::RPL_ISUPPORT, client.nickname,
        "CASEMAPPING=rfc1459", "CHANTYPES=#&+!", "PREFIX=(ohv)@%+", "CHANMODES=b,k,l,imnpst", "NICKLEN=30",
        ":are supported by this server")
    end

    def self.lusers(client : Client)
      nick = client.nickname
      user_repo = Infrastructure::ServiceLocator.user_repository
      channel_repo = Infrastructure::ServiceLocator.channel_repository

      user_count = user_repo.size
      invisible_count = user_repo.count(&.modes.includes?('i'))
      visible_count = user_count - invisible_count
      operator_count = user_repo.count(&.irc_operator?)
      server_count = Network::NetworkState.stats[:servers] + 1
      String.build do |io|
        Format.message(io, name, Numerics::RPL_LUSERCLIENT, nick, ":There are #{visible_count} users and #{invisible_count} invisible on #{server_count} server(s)")
        Format.message(io, name, Numerics::RPL_LUSEROP, nick, operator_count, ":IRC Operators online")
        Format.message(io, name, Numerics::RPL_LUSERUNKNOWN, nick, 0, ":unregistered connections")
        Format.message(io, name, Numerics::RPL_LUSERCHANNELS, nick, channel_repo.size, ":channels formed")
        Format.message(io, name, Numerics::RPL_LUSERME, nick, ":I have #{user_count} clients and #{server_count} servers")
        Format.message(io, name, Numerics::RPL_LOCALUSERS, nick, user_count, config.max_users, ":Current local users #{user_count}, max #{config.max_users}")
        Format.message(io, name, Numerics::RPL_GLOBALUSERS, nick, user_count, config.max_users, ":Current global users #{user_count}, max #{config.max_users}")
      end
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
      String.build do |io|
        Format.message(io, name, Numerics::RPL_MOTDSTART, client.nickname, ":- #{name} Message of the day -")
        Format.message(io, name, Numerics::RPL_MOTD, client.nickname, ":- Welcome to Circd Server")
        Format.message(io, name, Numerics::RPL_ENDOFMOTD, client.nickname, ":End of MOTD command")
      end
    end

    def self.clean_name
      ":" + name
    end

    def self.name
      config.server_name || config.host
    end

    def self.rehash_config! : Nil
      apply_config(File.read(@@config_file))
      Log.info { "#{@@config_file} reloaded by operator request" }
    end

    def self.connect_linked_server(host : String, port : Int32? = nil) : Bool
      linked_server = config.linked_servers.find do |server|
        server.host == host && (port.nil? || server.port == port)
      end
      return false unless linked_server
      return true if configured_link_connected?(linked_server)

      spawn supervise_link(linked_server)
      true
    end

    def self.shutdown_by_operator(reason : String) : Nil
      Log.warn { "Operator requested server shutdown: #{reason}" }
      ServerHandler.servers.each(&.close("Operator shutdown: #{reason}"))
      exit(0)
    end

    def self.restart_by_operator(reason : String) : Nil
      Log.warn { "Operator requested server restart: #{reason}" }
      ServerHandler.servers.each(&.close("Operator restart: #{reason}"))
      if executable_path = Process.executable_path
        Process.exec(executable_path, ARGV)
      else
        Log.error { "Operator restart failed: executable path is unavailable" }
        exit(1)
      end
    rescue ex
      Log.error(exception: ex) { "Operator restart failed" }
      exit(1)
    end

    def self.watch_config_file
      spawn do
        modification_time = File.info(@@config_file).modification_time
        loop do
          sleep 2.seconds
          begin
            current_modification_time = File.info(@@config_file).modification_time
            next if current_modification_time == modification_time

            file_content = File.read(@@config_file)
            if @@config_cache != file_content
              apply_config(file_content)
              Log.info { "#{@@config_file} changed, reloaded" }
            end
            modification_time = current_modification_time
          rescue ex
            Log.warn(exception: ex) { "Failed to reload #{@@config_file}" }
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

    private def self.apply_config(file_content : String) : Nil
      new_config = Config.from_yaml(file_content)
      new_config.validate_ssl!
      self.config = new_config
      @@config_cache = file_content
    end

    private def self.configure_line_persistence : Nil
      Network::LineState.configure_persistence(config.line_database, ENV["CIRCED_TEST"]? != "true" || ENV.has_key?("CIRCED_LINE_DB"))
    end
  end
end
