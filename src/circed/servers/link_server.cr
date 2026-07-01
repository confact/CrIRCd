require "../mixins/unified_messaging"
require "../network/ssl_socket"

module Circed
  class LinkServer
    include UnifiedMessaging

    getter name : String
    getter target_host : String
    getter target_port : Int32

    getter socket : Network::SSLSocket::IRCSocket? = nil

    @pingpong : Pingpong?

    @buffer = [] of String

    def initialize(@name : String, @target_host : String, @target_port : Int32, password : String, use_ssl : Bool = false, verify_ssl : Bool = false)
      # Create TCP connection
      tcp_socket = TCPSocket.new(@target_host, @target_port)

      # Wrap with SSL if needed
      @socket = if use_ssl
                  begin
                    # Create a minimal SSL config for client connections
                    ssl_yaml = <<-YAML
        enabled: true
        verify_mode: #{verify_ssl}
        YAML
                    ssl_config = Config::SSLConfig.from_yaml(ssl_yaml)

                    # Set connection timeout
                    tcp_socket.read_timeout = 15.seconds
                    tcp_socket.write_timeout = 15.seconds

                    context = Network::SSLSocket.create_client_context(ssl_config)
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

      handshake(password)
      setup([@name])
      listen
    end

    def initialize(socket : Network::SSLSocket::IRCSocket, buffer, remote_addr : Socket::IPAddress)
      @socket = socket
      @buffer = buffer
      @target_host = remote_addr.address
      @target_port = remote_addr.port
      @name = "" # Will be set during authentication

      authenticate_incoming_server
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

    def authenticate_incoming_server
      auth_state = AuthenticationState.new

      @buffer.each do |line|
        process_authentication_line(line, auth_state)
        return if auth_state.failed?
      end

      complete_authentication(auth_state)
    end

    private def process_authentication_line(line : String, auth_state : AuthenticationState) : Nil
      payload = FastIRC.parse_line(line)
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

      @name = payload.params[0]? || "unknown"
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
        until socket_ref.closed?
          FastIRC.parse(socket_ref) do |payload|
            dispatch_command(payload)
          end

          if closed?
            Log.info { "Server connection closed: #{@name}" }
            handle_disconnect("Connection lost")
            break
          end
        end
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
      when "PRIVMSG", "NOTICE", "TOPIC", "AWAY"
        handle_messaging_commands(payload)
      when "JOIN", "PART", "QUIT", "NICK", "MODE"
        handle_user_state_change(payload)
      when "KILL", "NJOIN"
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
      when "AWAY"
        handle_away_change(payload)
      end
    end

    private def handle_admin_commands(payload)
      case payload.command
      when "KILL"
        Commands::ServerCommands.kill(self, payload.params)
      when "NJOIN"
        Commands::ServerCommands.njoin(self, payload.params)
      end
    end

    def handle_server_message(payload)
      return if payload.params.size < 4

      server_name = payload.params[0]
      hopcount = payload.params[1].to_i? || 0
      token = payload.params[2]
      description = payload.params[3..]?.try(&.join(" ")) || ""
      description = description.lstrip(':')

      Log.info { "Remote server introducing: #{server_name} (hopcount: #{hopcount + 1})" }

      # Add to network state
      Network::NetworkState.add_server(server_name, hopcount + 1, description, nil, token)
      Network::NetworkState.add_server_link(@name, server_name)

      # Forward to other servers
      forward_message_to_peers(payload)
    end

    def handle_user_state_change(payload)
      user_introduction = user_introduction?(payload)

      if payload.command == "NICK" && !user_introduction
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
        handle_mode_message(payload)
      end

      # Forward to other servers and local clients
      forward_message_to_peers(payload)
      deliver_state_change_to_local_users(payload) unless user_introduction
    end

    def handle_nick_change(payload)
      return if payload.params.empty?

      if user_introduction?(payload)
        handle_user_introduction(payload)
        return
      end

      old_nick = extract_nickname(payload)
      new_nick = payload.params[0]

      if user = Network::NetworkState.get_user(old_nick)
        # Update network state
        Network::NetworkState.remove_user(old_nick)
        Network::NetworkState.add_user(new_nick, user.username, user.hostname, user.realname, user.server, user.hopcount)

        # Update channel memberships
        Network::NetworkState.channels.each do |_, channel|
          if channel.members.has_key?(old_nick)
            modes = channel.members.delete(old_nick)
            channel.members[new_nick] = modes if modes
          end
        end
      end

      Infrastructure::ServiceLocator.channel_repository.all.each do |channel|
        if modes = channel.members.delete(old_nick)
          channel.members[new_nick] = modes
        end
      end

      Log.debug { "Nick change: #{old_nick} -> #{new_nick}" }
    end

    private def handle_user_introduction(payload)
      return if payload.params.size < 7

      nickname = payload.params[0]
      hopcount = payload.params[1].to_i? || 1
      username = payload.params[2]
      hostname = payload.params[3]
      modes = payload.params[5]
      realname = payload.params[6..]?.try(&.join(" ")) || ""
      realname = realname.lstrip(':')

      Network::NetworkState.add_user(nickname, username, hostname, realname, @name, hopcount)

      if modes.starts_with?('+')
        user = Network::NetworkState.get_user(nickname)
        modes[1..].each_char { |mode| user.try(&.modes.<<(mode)) }
      end

      Log.debug { "Introduced remote user #{nickname} from #{@name}" }
    end

    private def user_introduction?(payload) : Bool
      payload.command == "NICK" && payload.prefix.nil? && payload.params.size >= 7
    end

    def handle_join_message(payload)
      return if payload.params.empty?

      nickname = extract_nickname(payload)
      channel_name = payload.params[0]

      Network::NetworkState.join_user_to_channel(nickname, channel_name)
      channel = Infrastructure::ServiceLocator.channel_repository.create_channel(channel_name)
      channel.add_member(nickname) unless channel.has_member?(nickname)
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

    def handle_mode_message(payload)
      return if payload.params.size < 2

      target = payload.params[0]
      modes = payload.params[1]

      if target.starts_with?('#') || target.starts_with?('&')
        # Channel mode change
        if channel = Network::NetworkState.get_channel(target)
          parse_channel_modes(channel, modes)
        end
      end

      Log.debug { "Mode change on #{target}: #{modes}" }
    end

    def handle_topic_change(payload)
      return if payload.params.size < 2

      channel_name = payload.params[0]
      topic = payload.params[1..]?.try(&.join(" ")) || ""
      topic = topic.lstrip(':')

      if channel = Network::NetworkState.get_channel(channel_name)
        channel.topic = topic
        channel.topic_set_by = payload.prefix.try(&.source)
        channel.topic_set_at = Time.utc
      end

      Log.debug { "Topic change for #{channel_name}: #{topic}" }
    end

    def handle_away_change(payload)
      return if payload.params.empty?

      nickname = payload.params[0]
      away_msg = payload.params[1..]?.try(&.join(" "))
      away_msg = away_msg.try(&.lstrip(':'))

      if user = Network::NetworkState.get_user(nickname)
        user.away_message = away_msg
      end

      Log.debug { "Away status change for #{nickname}" }
    end

    private def forward_message_to_peers(payload : FastIRC::Message) : Nil
      message = String.build { |io| payload.to_s(io) }

      ServerHandler.servers.each do |server|
        next if server == self
        server.send_message(message)
      end
    end

    private def extract_nickname(payload : FastIRC::Message) : String
      payload.prefix.try(&.source) || ""
    end

    private def parse_channel_modes(channel : Network::NetworkState::ChannelInfo, modes : String)
      adding = true
      modes.each_char do |char|
        case char
        when '+'
          adding = true
        when '-'
          adding = false
        else
          if adding
            channel.modes << char
          else
            channel.modes.delete(char)
          end
        end
      end
    end

    def setup(params)
      @pingpong = Pingpong.new(self)
      @name = params[0]

      # Add to server handler and network state
      ServerHandler.add_server(self)
      Network::NetworkState.add_server(@name, 1, "Connected Server", self)
      Network::NetworkState.add_server_link(Server.name, @name)

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

    # Use UnifiedMessaging methods - these are now consolidated

    def close(reason : String = "Closing connection")
      Log.info { "Closing server connection to #{@name}: #{reason}" }
      cleanup_pingpong

      # Send SQUIT and handle network cleanup
      handle_disconnect(reason)

      socket.try(&.close)
    end

    private def handle_disconnect(reason : String)
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
      @pingpong.try(&.stop_ping)
      @pingpong.try(&.stop_pong_check)
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

      if target.starts_with?('#') || target.starts_with?('&')
        # Channel message - deliver to all local users in channel
        deliver_to_local_channel(target, payload, sender_nick, message)
      else
        # Private message - deliver to local user if they exist
        deliver_to_local_user(target, payload, sender_nick, message)
      end
    end

    private def deliver_to_local_channel(channel_name : String, payload, sender_nick : String, message : String)
      if channel = Network::NetworkState.get_channel(channel_name)
        # Find local users in this channel
        user_repository = Infrastructure::ServiceLocator.user_repository
        local_users = channel.members.keys.select do |nick|
          user_repository.get_client(nick)
        end

        # Send message to each local user
        local_users.each do |local_nick|
          if client = user_repository.get_client(local_nick)
            # Don't send message back to the sender if they're local
            next if local_nick == sender_nick

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

      # Send QUIT to all local users who shared channels with this user
      send_quit_to_shared_local_users(sender_nick, message)
    end

    private def deliver_nick_to_local_users(payload)
      return if payload.params.empty?

      old_nick = extract_nickname(payload)
      # new_nick = payload.params[0]  # Removed unused variable
      message = format_state_change_message(payload)

      # Send NICK change to all local users who shared channels with this user
      send_nick_to_shared_local_users(old_nick, message)
    end

    private def deliver_mode_to_local_users(payload)
      return if payload.params.size < 2

      target = payload.params[0]

      if target.starts_with?('#') || target.starts_with?('&')
        # Channel mode change
        message = format_state_change_message(payload)
        send_to_local_channel_members(target, message)
      end
    end

    private def format_state_change_message(payload) : String
      sender_nick = extract_nickname(payload)

      if user_info = Network::NetworkState.get_user(sender_nick)
        hostmask = "#{sender_nick}!#{user_info.username}@#{user_info.hostname}"
        ":#{hostmask} #{payload.command}#{format_params(payload.params)}"
      else
        # Fallback
        ":#{sender_nick}!unknown@unknown #{payload.command}#{format_params(payload.params)}"
      end
    end

    private def format_params(params : Array(String)) : String
      return "" if params.empty?

      String.build do |io|
        params.each_with_index do |param, index|
          io << ' '
          if index == params.size - 1 && (param.empty? || param.includes?(' ') || param.starts_with?(':'))
            io << ':'
            io << param.lstrip(':')
          else
            io << param
          end
        end
      end
    end

    private def send_to_local_channel_members(channel_name : String, message : String, exclude_nick : String? = nil)
      if channel = Network::NetworkState.get_channel(channel_name)
        user_repository = Infrastructure::ServiceLocator.user_repository
        local_users = channel.members.keys.select do |nick|
          user_repository.get_client(nick)
        end

        local_users.each do |local_nick|
          next if exclude_nick && local_nick == exclude_nick

          if client = user_repository.get_client(local_nick)
            client.send_message(message)
          end
        end
      end
    end

    private def send_quit_to_shared_local_users(remote_nick : String, message : String)
      # Find all channels the remote user was in
      affected_channels = Network::NetworkState.channels.select do |_, channel|
        channel.members.has_key?(remote_nick)
      end

      # Collect all local users who shared channels (avoid duplicates)
      user_repository = Infrastructure::ServiceLocator.user_repository
      local_users = Set(String).new
      affected_channels.each do |_, channel|
        channel.members.keys.each do |nick|
          local_users << nick if user_repository.get_client(nick)
        end
      end

      # Send QUIT message to each local user
      local_users.each do |local_nick|
        if client = user_repository.get_client(local_nick)
          client.send_message(message)
        end
      end
    end

    private def send_nick_to_shared_local_users(old_nick : String, message : String)
      # Similar to QUIT - find all local users who shared channels
      affected_channels = Network::NetworkState.channels.select do |_, channel|
        channel.members.has_key?(old_nick)
      end

      user_repository = Infrastructure::ServiceLocator.user_repository
      local_users = Set(String).new
      affected_channels.each do |_, channel|
        channel.members.keys.each do |nick|
          local_users << nick if user_repository.get_client(nick)
        end
      end

      local_users.each do |local_nick|
        if client = user_repository.get_client(local_nick)
          client.send_message(message)
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
