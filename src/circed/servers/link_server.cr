require "../network/ssl_socket"

module Circed
  class LinkServer
    OUTBOUND_QUEUE_CAPACITY = 4096
    OUTBOUND_BATCH_MESSAGES =  128
    OUTBOUND_BATCH_BYTES    = 256 * 1024

    getter name : String
    getter target_host : String
    getter target_port : Int32

    getter socket : Network::SSLSocket::IRCSocket? = nil

    @pingpong : Pingpong?

    @disconnected : Bool = false
    @registered : Bool = false
    @outbound_messages : ::Channel(String) = ::Channel(String).new(OUTBOUND_QUEUE_CAPACITY)
    @direct_writes : Bool = ENV["CIRCED_TEST"]? == "true"
    @socket_write_mutex : Mutex = Mutex.new

    def initialize(@name : String, @target_host : String, @target_port : Int32, password : String, use_ssl : Bool = false, verify_ssl : Bool = false)
      # Create TCP connection
      tcp_socket = TCPSocket.new(@target_host, @target_port)

      # Wrap with SSL if needed
      @socket = if use_ssl
                  begin
                    # Set connection timeout
                    tcp_socket.read_timeout = 15.seconds
                    tcp_socket.write_timeout = 15.seconds

                    context = Network::SSLSocket.create_client_context(verify_mode: verify_ssl)
                    ssl_socket = Network::SSLSocket.wrap_client_socket(tcp_socket, context, @target_host)

                    if peer_info = Network::SSLSocket.get_peer_info(ssl_socket)
                      Log.info { "Established SSL connection to #{@target_host}:#{@target_port} (#{peer_info})" }
                    else
                      Log.info { "Established SSL connection to #{@target_host}:#{@target_port}" }
                    end

                    ssl_socket
                  rescue ex : OpenSSL::SSL::Error
                    Log.error { "SSL connection failed to #{@target_host}:#{@target_port}: #{ex.message}" }
                    tcp_socket.close
                    raise ex
                  rescue ex : IO::TimeoutError
                    Log.error { "SSL connection timed out to #{@target_host}:#{@target_port}" }
                    tcp_socket.close
                    raise "SSL connection timeout"
                  rescue ex
                    Log.error { "Failed to establish SSL connection to #{@target_host}:#{@target_port}: #{ex.message}" }
                    tcp_socket.close
                    raise ex
                  end
                else
                  tcp_socket
                end

      start_outbound_writer unless @direct_writes
      handshake(password)
      listen
    end

    def initialize(socket : Network::SSLSocket::IRCSocket, buffer : Array(String), remote_addr : Socket::IPAddress)
      @socket = socket
      @target_host = remote_addr.address
      @target_port = remote_addr.port
      @name = "" # Will be set during authentication

      start_outbound_writer unless @direct_writes
      authenticate_incoming_server(buffer)
      listen
    end

    def handshake(password : String) : Nil
      # IRC server handshake protocol
      # Send PASS command for authentication
      safe_send("PASS #{password}")

      # Send SERVER command with our server info
      # Format: SERVER <servername> <hopcount> :<info>
      safe_send("SERVER #{Server.name} 1 :Circed IRC Server")

      Log.info { "Sent handshake to #{@target_host}:#{@target_port}" }
    end

    def authenticate_incoming_server(buffer : Array(String))
      auth_state = AuthenticationState.new

      buffer.each do |line|
        process_authentication_line(line, auth_state)
        break if auth_state.failed?
      end
      return if auth_state.failed?

      complete_authentication(auth_state)
    end

    private def process_authentication_line(line : String, auth_state : AuthenticationState) : Nil
      payload = FastIRC.parse_line(line, strict: true)
      case payload.command
      when "PASS"
        process_pass_command(payload, auth_state)
      when "SERVER"
        process_server_command(payload, auth_state)
      end
    rescue ex
      Log.warn { "Failed to parse IRC line during authentication: #{line} - #{ex.message}" }
    end

    private def process_pass_command(payload, auth_state)
      password = payload.params[0]?
      if password == Server.config.link_password
        auth_state.authenticated = true
        Log.info { "Server authentication successful from #{@target_host}" }
      else
        Log.error { "Server authentication failed from #{@target_host}" }
        send_error("Bad Password")
        auth_state.failed = true
      end
    end

    private def process_server_command(payload, auth_state)
      unless auth_state.authenticated?
        Log.error { "Server tried to introduce without authentication: #{@target_host}" }
        send_error("Not authenticated")
        auth_state.failed = true
        return
      end

      server_name = payload.params[0]? || "unknown"
      if server_name == Server.name || Network::NetworkState.get_server(server_name)
        Log.error { "Server #{server_name} introduced a duplicate route" }
        send_error("Server #{server_name} already exists")
        auth_state.failed = true
        return
      end

      @name = server_name
      auth_state.server_introduced = true
      Log.info { "Server #{@name} introduced from #{@target_host}" }

      # Send our server info back
      safe_send("SERVER #{Server.name} 1 :Circed IRC Server")
    end

    private def complete_authentication(auth_state)
      unless auth_state.complete?
        Log.error { "Incomplete handshake from #{@target_host}" }
        send_error("Incomplete handshake")
        return
      end

      setup([@name])
    end

    private class AuthenticationState
      property? authenticated : Bool = false
      property? server_introduced : Bool = false
      property? failed : Bool = false

      def complete?
        authenticated? && server_introduced?
      end
    end

    def listen : Nil
      return unless socket_ref = socket

      begin
        reader = FastIRC::Reader.new(socket_ref, strict: true)
        while payload = reader.next
          dispatch_command(payload)
        end

        Log.info { "Server connection closed: #{@name}" }
        handle_disconnect("Connection lost")
      rescue ex : IO::Error | OpenSSL::SSL::Error
        Log.warn { "Server connection lost for #{@name}: #{ex.message}" }
        handle_disconnect("Connection lost")
      rescue ex
        Log.error { "Server link #{@name} failed: #{ex.message}" }
        handle_disconnect("Connection error")
      end
    end

    private def dispatch_command(payload)
      Performance::Metrics.increment_command(payload.command)

      case payload.command
      when "ERROR", "PING", "PONG"
        handle_connection_commands(payload)
      when "SERVER", "SQUIT"
        handle_server_commands(payload)
      when "PRIVMSG", "NOTICE", "TOPIC", "AWAY", "WALLOPS"
        handle_messaging_commands(payload)
      when "JOIN", "PART", "QUIT", "NICK", "MODE"
        handle_user_state_change(payload)
      when "KILL", "NJOIN", Domain::LineBan::GLINE
        handle_admin_commands(payload)
      when "EOB", "LINKS", "STATS", "TIME", "VERSION", "ADMIN"
        Network::BurstProtocol.process_burst_message(payload.command, payload.params, self)
      else
        Log.debug { "Unhandled server command: #{payload.command}" }
      end
    end

    private def handle_connection_commands(payload)
      case payload.command
      when "ERROR"
        handle_error(payload)
      when "PING"
        ping(payload.params)
      when "PONG"
        pong(payload.params)
      end
    end

    private def handle_server_commands(payload)
      case payload.command
      when "SERVER"
        handle_server_message(payload)
      when "SQUIT"
        Commands::ServerCommands.squit(self, payload.params)
      end
    end

    private def handle_messaging_commands(payload)
      case payload.command
      when "PRIVMSG", "NOTICE"
        handle_message_delivery(payload)
      when "TOPIC"
        handle_topic_change(payload)
        forward_message_to_peers(payload)
      when "AWAY"
        handle_away_change(payload)
      when "WALLOPS"
        Commands::ServerCommands.wallops(self, payload.params)
      end
    end

    private def handle_admin_commands(payload)
      case payload.command
      when "KILL"
        Commands::ServerCommands.kill(self, payload.params)
      when "NJOIN"
        Commands::ServerCommands.njoin(self, payload.params)
      when Domain::LineBan::GLINE
        Commands::ServerCommands.gline(self, payload.params)
      end
    end

    def handle_server_message(payload)
      unless @registered
        return if payload.params.size < 3

        setup([payload.params[0]])
        return
      end

      return if payload.params.size < 4

      server_name = payload.params[0]
      hopcount = payload.params[1].to_i? || 0
      token = payload.params[2]
      description = Utils::IrcUtils.trailing_param(payload.params, 3)

      Log.info { "Remote server introducing: #{server_name} (hopcount: #{hopcount + 1})" }

      unless Network::NetworkState.add_server(server_name, hopcount + 1, description, nil, token) &&
             Network::NetworkState.add_server_link(@name, server_name)
        send_error("Server #{server_name} already exists")
        return
      end

      # Forward to other servers
      forward_message_to_peers(payload)
    end

    def handle_user_state_change(payload)
      user_introduction = user_introduction?(payload)

      if user_introduction
        forward_message_to_peers(payload) if handle_user_introduction(payload)
        return
      end

      if payload.command == "NICK"
        deliver_state_change_to_local_users(payload)
        handle_nick_change(payload)
        forward_message_to_peers(payload)
        return
      end

      if payload.command == "QUIT"
        deliver_state_change_to_local_users(payload)
        handle_quit_message(payload)
        forward_message_to_peers(payload)
        return
      end

      internal_mode = false
      case payload.command
      when "NICK"
        handle_nick_change(payload)
      when "JOIN"
        handle_join_message(payload)
      when "PART"
        handle_part_message(payload)
      when "QUIT"
        handle_quit_message(payload)
      when "MODE"
        internal_mode = handle_mode_message(payload)
      end

      # Forward to other servers and local clients
      forward_message_to_peers(payload)
      deliver_state_change_to_local_users(payload) unless internal_mode
    end

    def handle_nick_change(payload)
      return if payload.params.empty?

      old_nick = extract_nickname(payload)
      new_nick = payload.params[0]

      if user = Network::NetworkState.get_user(old_nick)
        # Update network state
        Network::NetworkState.remove_user(old_nick)
        Network::NetworkState.add_user(new_nick, user.username, user.hostname, user.realname, user.server, user.hopcount)

        # Update channel memberships
        Network::NetworkState.channels.each_value do |channel|
          channel.rename_member(old_nick, new_nick)
        end
      end

      Infrastructure::ServiceLocator.channel_repository.rename_member(old_nick, new_nick)

      Log.debug { "Nick change: #{old_nick} -> #{new_nick}" }
    end

    private def handle_user_introduction(payload)
      return false if payload.params.size < 8

      nickname = payload.params[0]
      hopcount = payload.params[1].to_i? || 1
      connected_at = Time.unix(payload.params[2].to_i64? || Time.utc.to_unix)
      username = payload.params[3]
      hostname = payload.params[4]
      server_name = payload.params[5]
      modes = payload.params[6]
      realname = Utils::IrcUtils.trailing_param(payload.params, 7)

      return false unless Network::NetworkState.add_user(
                            nickname, username, hostname, realname, server_name, hopcount, connected_at
                          )

      if modes.starts_with?('+')
        user = Network::NetworkState.get_user(nickname)
        modes.each_char { |mode| user.try(&.modes.<<(mode)) unless mode == '+' }
      end

      Log.debug { "Introduced remote user #{nickname} from #{@name}" }
      true
    end

    private def user_introduction?(payload) : Bool
      payload.command == "NICK" && payload.prefix.nil? && payload.params.size >= 8
    end

    def handle_join_message(payload)
      return if payload.params.empty?

      nickname = extract_nickname(payload)
      channel_name = payload.params[0]

      Network::NetworkState.join_user_to_channel(nickname, channel_name)
      channel_repository = Infrastructure::ServiceLocator.channel_repository
      channel = channel_repository.create_channel(channel_name)
      channel_repository.add_member(channel.name, nickname) unless channel.has_member?(nickname)
      Log.debug { "User #{nickname} joined #{channel_name}" }
    end

    def handle_part_message(payload)
      return if payload.params.empty?

      nickname = extract_nickname(payload)
      channel_name = payload.params[0]

      Network::NetworkState.part_user_from_channel(nickname, channel_name)
      Infrastructure::ServiceLocator.channel_repository.part_user(channel_name, nickname)
      Log.debug { "User #{nickname} parted #{channel_name}" }
    end

    def handle_quit_message(payload)
      nickname = extract_nickname(payload)

      Network::NetworkState.remove_user(nickname)
      Infrastructure::ServiceLocator.channel_repository.remove_user_from_all_channels(nickname)
      Log.debug { "User #{nickname} quit" }
    end

    def handle_mode_message(payload) : Bool
      return false if payload.params.size < 2

      target = payload.params[0]
      if timestamp = payload.params[1].to_i64?
        modes = payload.params[2]? || "+"
        created_at = Time.unix(timestamp)
        parameter_index = 3
        internal_mode = true
      else
        modes = payload.params[1]
        created_at = nil
        parameter_index = 2
        internal_mode = false
      end

      if Utils::IrcUtils.valid_channel_name?(target)
        Network::NetworkState.apply_channel_modes(target, modes, payload.params, created_at, parameter_index)
      elsif user = Network::NetworkState.get_user(target)
        parse_modes(user.modes, modes)
      end

      Log.debug { "Mode change on #{target}: #{modes}" }
      internal_mode
    end

    def handle_topic_change(payload)
      return if payload.params.size < 2

      channel_name = payload.params[0]
      if payload.params.size >= 5 && (channel_timestamp = payload.params[1].to_i64?) &&
         (topic_timestamp = payload.params[2].to_i64?)
        topic = Utils::IrcUtils.trailing_param(payload.params, 4)
        updated = Network::NetworkState.set_channel_topic(
          channel_name,
          topic,
          payload.params[3],
          Time.unix(topic_timestamp),
          Time.unix(channel_timestamp)
        )
      else
        topic = Utils::IrcUtils.trailing_param(payload.params, 1)
        updated = Network::NetworkState.set_channel_topic(channel_name, topic, payload.prefix.try(&.source))
      end

      Network::NetworkState.sync_channel_repository(channel_name) if updated

      Log.debug { "Topic change for #{channel_name}: #{topic}" }
    end

    def handle_away_change(payload)
      return if payload.params.empty?

      nickname = payload.params[0]
      away_msg = payload.params.size > 1 ? Utils::IrcUtils.trailing_param(payload.params, 1) : nil

      Network::NetworkState.set_user_away(nickname, away_msg)

      Log.debug { "Away status change for #{nickname}" }
    end

    private def forward_message_to_peers(payload : FastIRC::Message) : Nil
      ServerHandler.servers.each do |server|
        next if server == self
        server.send_message(payload)
      end
    end

    private def extract_nickname(payload : FastIRC::Message) : String
      payload.prefix.try(&.source) || ""
    end

    private def parse_modes(target_modes : Set(Char), modes : String)
      adding = true
      modes.each_char do |char|
        case char
        when '+'
          adding = true
        when '-'
          adding = false
        else
          if adding
            target_modes << char
          else
            target_modes.delete(char)
          end
        end
      end
    end

    def setup(params)
      @pingpong = Pingpong.new(self)
      @name = params[0]

      if @name == Server.name || Network::NetworkState.get_server(@name)
        @disconnected = true
        send_error("Server #{@name} already exists")
        return
      end

      # Add to server handler and network state
      ServerHandler.add_server(self)
      unless Network::NetworkState.add_server(@name, 1, "Connected Server", self) &&
             Network::NetworkState.add_server_link(Server.name, @name)
        ServerHandler.remove_server(self)
        @disconnected = true
        send_error("Server #{@name} creates a duplicate route")
        return
      end
      @registered = true

      # Start burst protocol - send our network state to the new server
      spawn do
        begin
          Network::BurstProtocol.send_burst(self)
        rescue ex
          Log.error { "Failed to send burst to #{@name}: #{ex.message}" }
        end
      end
    end

    def pong(params : Array(String))
      @pingpong.try(&.pong(params))
      Log.debug { "PONG #{@name}" }
      # send_message("PING :#{@name} :localhost")
    end

    def ping(params : Array(String))
      @pingpong.try(&.ping(params))
      # return if @last_checked && @last_checked.not_nil! < 5.seconds.ago
    end

    def closed? : Bool
      socket.try(&.closed?) || false
    end

    def safe_send(message : String) : Bool
      line = message.ends_with?("\r\n") ? message : "#{message}\r\n"
      enqueue_line(line)
    end

    def safe_send(message : FastIRC::Message) : Bool
      enqueue_line(String.build { |io| message.to_s(io) })
    end

    private def enqueue_line(line : String) : Bool
      return false if closed?

      return write_to_socket(line) if @direct_writes
      return false if @outbound_messages.closed?

      select
      when @outbound_messages.send(line)
        Performance::Metrics.increment_messages
        true
      else
        close("Server link outbound queue full")
        false
      end
    rescue Channel::ClosedError
      false
    end

    def send_message(message : String)
      safe_send(message)
    end

    def send_message(message : FastIRC::Message)
      safe_send(message)
    end

    private def send_error(message : String) : Nil
      safe_send("ERROR :#{message}")
      close
    end

    def close(reason : String = "Closing connection")
      Log.info { "Closing server connection to #{@name}: #{reason}" }
      cleanup_pingpong

      # Send SQUIT and handle network cleanup
      handle_disconnect(reason)

      close_transport
    end

    def close_from_peer(reason : String)
      Log.info { "Closing server connection to #{@name}: #{reason}" }
      @disconnected = true
      ServerHandler.remove_server(self)
      cleanup_pingpong
      close_transport
    end

    private def handle_disconnect(reason : String)
      return if @disconnected
      @disconnected = true
      return if @name.empty?

      # Send SQUIT to notify other servers about the disconnect
      propagate_squit_message(reason)

      # Remove from server handler and clean up network state
      ServerHandler.remove_server(self)
      Network::NetworkState.remove_server(@name, send_squit: false) # We already sent SQUIT above
    end

    private def propagate_squit_message(reason : String)
      # Send SQUIT to all other connected servers (except the one that's disconnecting)
      squit_message = "SQUIT #{@name} :#{reason}"

      ServerHandler.servers.each do |server|
        next if server == self
        server.safe_send(squit_message)
      end

      Log.info { "Sent SQUIT for #{@name} to remaining servers" }
    end

    private def cleanup_pingpong
      @pingpong.try(&.stop)
    end

    private def close_transport
      close_outbound_queue
      socket.try(&.close)
    end

    private def start_outbound_writer : Nil
      spawn do
        outbound_writer_loop
      end
    end

    private def outbound_writer_loop : Nil
      while first_message = @outbound_messages.receive?
        batch = OutboundBatch.build(@outbound_messages, first_message, OUTBOUND_BATCH_MESSAGES, OUTBOUND_BATCH_BYTES)
        break unless write_to_socket(batch)
      end
    ensure
      close_outbound_queue
    end

    private def write_to_socket(message : String) : Bool
      return false unless socket_ref = socket

      @socket_write_mutex.synchronize do
        socket_ref.write(message.to_slice)
        socket_ref.flush
      end
      true
    rescue ex : IO::Error | IO::TimeoutError | OpenSSL::SSL::Error
      Log.debug(exception: ex) { "Closing server link after write failure" }
      handle_disconnect("Write failure")
      socket.try(&.close)
      false
    end

    private def close_outbound_queue : Nil
      @outbound_messages.close
    end

    def handle_message(message)
      return if closed?
      send_message(message)
    end

    def handle_error(payload)
      Log.error { "Server #{@name} sent ERROR: #{payload.params.join(" ")}" }
      close
    end

    def handle_message_delivery(payload)
      # Forward message to all other connected servers except the sender
      forward_message_to_peers(payload)

      # Forward to local clients if the target is a local user/channel
      deliver_to_local_targets(payload)
    end

    private def deliver_to_local_targets(payload)
      return if payload.params.empty?

      target = payload.params[0]
      message = payload.params[1]? || ""
      sender_nick = extract_nickname(payload)

      if Utils::IrcUtils.valid_channel_name?(target)
        # Channel message - deliver to all local users in channel
        deliver_to_local_channel(target, payload, sender_nick, message)
      else
        # Private message - deliver to local user if they exist
        deliver_to_local_user(target, payload, sender_nick, message)
      end
    end

    private def deliver_to_local_channel(channel_name : String, payload, sender_nick : String, message : String)
      if channel = Network::NetworkState.get_channel(channel_name)
        user_repository = Infrastructure::ServiceLocator.user_repository

        channel.members.each_key do |local_nick|
          next if Domain::CaseMapping.same?(local_nick, sender_nick)

          if client = user_repository.get_client(local_nick)
            formatted_message = format_message_for_client(payload, message)
            client.send_message(formatted_message)
          end
        end
      end
    end

    private def deliver_to_local_user(target_nick : String, payload, sender_nick : String, message : String)
      user_repository = Infrastructure::ServiceLocator.user_repository
      if client = user_repository.get_client(target_nick)
        formatted_message = format_message_for_client(payload, message)
        client.send_message(formatted_message)
      end
    end

    private def format_message_for_client(payload, message : String) : String
      # Format: ":sender!user@host COMMAND target :message"
      sender_nick = extract_nickname(payload)
      target = payload.params[0]

      if user_info = Network::NetworkState.get_user(sender_nick)
        hostmask = "#{sender_nick}!#{user_info.username}@#{user_info.hostname}"
        ":#{hostmask} #{payload.command} #{target} :#{message}"
      else
        # Fallback if user info not available
        ":#{sender_nick}!unknown@unknown #{payload.command} #{target} :#{message}"
      end
    end

    private def deliver_state_change_to_local_users(payload)
      case payload.command
      when "JOIN"
        deliver_join_to_local_users(payload)
      when "PART"
        deliver_part_to_local_users(payload)
      when "QUIT"
        deliver_quit_to_local_users(payload)
      when "NICK"
        deliver_nick_to_local_users(payload)
      when "MODE"
        deliver_mode_to_local_users(payload)
      end
    end

    private def deliver_join_to_local_users(payload)
      return if payload.params.empty?

      sender_nick = extract_nickname(payload)
      channel_name = payload.params[0]

      Network::NetworkState.get_channel(channel_name).try do |_|
        message = format_state_change_message(payload)
        send_to_local_channel_members(channel_name, message, sender_nick)
      end
    end

    private def deliver_part_to_local_users(payload)
      return if payload.params.empty?

      sender_nick = extract_nickname(payload)
      channel_name = payload.params[0]

      message = format_state_change_message(payload)
      send_to_local_channel_members(channel_name, message, sender_nick)
    end

    private def deliver_quit_to_local_users(payload)
      sender_nick = extract_nickname(payload)
      message = format_state_change_message(payload)

      send_to_shared_local_users(sender_nick, message)
    end

    private def deliver_nick_to_local_users(payload)
      return if payload.params.empty?

      old_nick = extract_nickname(payload)
      message = format_state_change_message(payload)

      send_to_shared_local_users(old_nick, message)
    end

    private def deliver_mode_to_local_users(payload)
      return if payload.params.size < 2

      target = payload.params[0]

      if Utils::IrcUtils.valid_channel_name?(target)
        # Channel mode change
        message = format_state_change_message(payload)
        send_to_local_channel_members(target, message)
      end
    end

    private def format_state_change_message(payload) : String
      sender_nick = extract_nickname(payload)
      prefix = if user_info = Network::NetworkState.get_user(sender_nick)
                 FastIRC::Prefix.new(source: sender_nick, user: user_info.username, host: user_info.hostname)
               else
                 FastIRC::Prefix.new(source: sender_nick, user: "unknown", host: "unknown")
               end
      FastIRC::Message.new(
        payload.command,
        payload.params,
        prefix: prefix,
        tags: payload.tags?
      ).to_s
    end

    private def send_to_local_channel_members(channel_name : String, message : String, exclude_nick : String? = nil)
      if channel = Network::NetworkState.get_channel(channel_name)
        user_repository = Infrastructure::ServiceLocator.user_repository
        channel.members.each_key do |local_nick|
          next if exclude_nick && Domain::CaseMapping.same?(local_nick, exclude_nick)

          if client = user_repository.get_client(local_nick)
            client.send_message(message)
          end
        end
      end
    end

    private def send_to_shared_local_users(remote_nick : String, message : String)
      user_repository = Infrastructure::ServiceLocator.user_repository
      notified = Set(String).new
      Network::NetworkState.channels.each_value do |channel|
        next unless channel.has_member?(remote_nick)

        channel.members.each_key do |nick|
          next if notified.includes?(nick)
          if client = user_repository.get_client(nick)
            notified << nick
            client.send_message(message)
          end
        end
      end
    end

    def nickname
      @name
    end

    def host
      @target_host
    end
  end
end
