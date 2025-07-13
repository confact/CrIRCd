module Circed
  class LinkServer
    include SocketHelper

    getter name : String
    getter target_host : String
    getter target_port : Int32

    getter socket : IPSocket? = nil

    @pingpong : Pingpong?

    @buffer : Array(String) = [] of String

    def initialize(name, target_host, target_port, password)
      @name = name
      @target_host = target_host
      @target_port = target_port

      @socket = TCPSocket.new(@target_host, @target_port)
      handshake(password)

      listen
    end

    def initialize(socket, buffer)
      @socket = socket
      @buffer = buffer
      remote_addr = socket.remote_address
      @target_host = remote_addr.address
      @target_port = remote_addr.port
      @name = ""  # Will be set during authentication

      authenticate_incoming_server
      listen
    end

    def handshake(password)
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

    private def process_authentication_line(line, auth_state)
      begin
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
      unless auth_state.authenticated
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
      property authenticated : Bool = false
      property server_introduced : Bool = false
      property failed : Bool = false

      def complete?
        authenticated && server_introduced
      end

      def failed?
        failed
      end
    end

    def listen
      while !socket.not_nil!.closed?
        FastIRC.parse(socket.not_nil!) do |payload|
          dispatch_command(payload)
        end

        if closed?
          Log.info { "Server connection closed: #{@name}" }
          handle_disconnect("Connection lost")
          break
        end
      end
    end

    private def dispatch_command(payload)
      case payload.command
      when "ERROR"
        handle_error(payload)
      when "PING"
        ping(payload.params)
      when "PONG"
        pong(payload.params)
      when "SERVER"
        handle_server_message(payload)
      when "PRIVMSG"
        forward_message_to_peers(payload)
      when "JOIN", "PART", "QUIT", "NICK", "MODE"
        handle_user_state_change(payload)
      when "SQUIT"
        Commands::ServerCommands.squit(self, payload.params)
      when "KILL"
        Commands::ServerCommands.kill(self, payload.params)
      when "NJOIN"
        Commands::ServerCommands.njoin(self, payload.params)
      when "TOPIC"
        handle_topic_change(payload)
      when "AWAY"
        handle_away_change(payload)
      when "EOB", "LINKS", "STATS", "TIME", "VERSION", "ADMIN"
        Network::BurstProtocol.process_burst_message(payload.command, payload.params, self)
      else
        Log.debug { "Unhandled server command: #{payload.command}" }
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
      deliver_state_change_to_local_users(payload)
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
        Network::NetworkState.channels.each do |channel_name, channel|
          if channel.members.has_key?(old_nick)
            modes = channel.members.delete(old_nick)
            channel.members[new_nick] = modes if modes
          end
        end
      end
      
      Log.debug { "Nick change: #{old_nick} -> #{new_nick}" }
    end

    def handle_join_message(payload)
      return if payload.params.empty?
      
      nickname = extract_nickname(payload)
      channel_name = payload.params[0]
      
      Network::NetworkState.join_user_to_channel(nickname, channel_name)
      Log.debug { "User #{nickname} joined #{channel_name}" }
    end

    def handle_part_message(payload)
      return if payload.params.empty?
      
      nickname = extract_nickname(payload)
      channel_name = payload.params[0]
      
      Network::NetworkState.part_user_from_channel(nickname, channel_name)
      Log.debug { "User #{nickname} parted #{channel_name}" }
    end

    def handle_quit_message(payload)
      nickname = extract_nickname(payload)
      
      Network::NetworkState.remove_user(nickname)
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

    private def forward_message_to_peers(payload)
      message = String.build { |io| payload.to_s(io) }
      ServerHandler.servers.each do |server|
        next if server == self
        server.send_message(message)
      end
    end

    private def extract_nickname(payload)
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

    def send_message(message)
      Log.info { message }
      safe_send(message)
    end

    def send_message(prefix, command, *params)
      send_irc_message(command, params.to_a, prefix)
    end

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

    def handle_privmsg(payload)
      # Forward PRIVMSG to all other connected servers except the sender
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
            
            formatted_message = format_privmsg_for_client(payload, message)
            client.send_message(formatted_message)
          end
        end
      end
    end

    private def deliver_to_local_user(target_nick : String, payload, sender_nick : String, message : String)
      user_repository = Infrastructure::ServiceLocator.user_repository
      if client = user_repository.get_client(target_nick)
        formatted_message = format_privmsg_for_client(payload, message)
        client.send_message(formatted_message)
      end
    end

    private def format_privmsg_for_client(payload, message : String) : String
      # Format: ":sender!user@host PRIVMSG target :message"
      sender_nick = extract_nickname(payload)
      target = payload.params[0]
      
      if user_info = Network::NetworkState.get_user(sender_nick)
        hostmask = "#{sender_nick}!#{user_info.username}@#{user_info.hostname}"
        ":#{hostmask} PRIVMSG #{target} :#{message}"
      else
        # Fallback if user info not available
        ":#{sender_nick}!unknown@unknown PRIVMSG #{target} :#{message}"
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
      
      if channel = Network::NetworkState.get_channel(channel_name)
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
      new_nick = payload.params[0]
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
        ":#{hostmask} #{payload.command} #{payload.params.join(" ")}"
      else
        # Fallback
        ":#{sender_nick}!unknown@unknown #{payload.command} #{payload.params.join(" ")}"
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