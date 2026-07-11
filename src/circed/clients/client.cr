require "../network/ssl_socket"
require "../actions/starttls"

module Circed
  class Client
    OUTBOUND_QUEUE_CAPACITY = 1024
    OUTBOUND_BATCH_MESSAGES =   64
    OUTBOUND_BATCH_BYTES    = 64 * 1024
    MAX_MESSAGE_BYTES       = 512
    IRC_LINE_END            = "\r\n"

    property socket : Network::SSLSocket::IRCSocket? = nil
    getter host : String?
    getter hostname : String
    getter ip_address : String
    getter nickname : String?
    getter hostmask : String?
    property last_activity : Time
    getter signon_time : Time

    getter user : User?
    property? registered : Bool = false
    property password : String?

    @buffer : Array(String)?
    @shutdown : Bool = false
    @outbound_messages : ::Channel(String)
    @direct_writes : Bool
    @socket_write_mutex : Mutex
    @last_ping : Time?
    @last_pong : Time?
    @hostname_lookup : Channel(String?)?
    @rate_limiter : Services::RateLimiter

    def initialize(@socket : Network::SSLSocket::IRCSocket?, buffer, ip_address : String? = nil)
      @buffer = buffer
      @outbound_messages = ::Channel(String).new(OUTBOUND_QUEUE_CAPACITY)
      @direct_writes = ENV["CIRCED_TEST"]? == "true"
      @socket_write_mutex = Mutex.new
      @rate_limiter = Services::RateLimiter.new
      @ip_address = ip_address || remote_ip_address(@socket)
      @host = if sock = @socket
                case sock
                when TCPSocket
                  sock.remote_address.to_s
                else
                  "ssl_client"
                end
              end
      @hostname = ip_address ? Hostname.get_hostname(ip_address) : initial_hostname(@socket)
      @hostname_lookup = start_hostname_lookup(@hostname)
      set_hostmask
      @last_activity = Time.utc
      @signon_time = Time.utc
      @last_pong = @signon_time
      start_outbound_writer unless @direct_writes
    end

    def setup
      message_handling
    end

    def message_handling
      return unless socket

      if buffer = @buffer
        @buffer = nil
        buffer.each do |buff|
          parse_message(buff)
        end
      end

      if current_socket = socket
        read_messages(current_socket)

        cleanup_after_disconnect
      end
    rescue e : IO::Error
      Log.warn(exception: e) { "IO Error" }
      cleanup_after_disconnect
    rescue e : Circed::ClosedClient
      remove_registered_client
    rescue e : Exception
      Log.error(exception: e) { "Error" }
      cleanup_after_disconnect
    end

    def user=(users_messages : Array(String))
      mode = users_messages[1]
      username = users_messages.first
      realname = users_messages[3].lchop(':')
      @user = User.new(mode, username, realname)
      set_hostmask
      Log.debug { "Set user to: #{user}" }

      # Create domain user in repository if we have a nickname
      if nickname = @nickname
        register_domain_user(nickname, username, realname, mode)
      end

      complete_registration
    end

    def set_hostmask
      temp_hostmask = get_hostmask
      @hostmask = temp_hostmask
      Log.debug { "Set hostmask to: #{hostmask}" }
    end

    def quit(_message)
      shutdown
      close
    end

    def send_message(message)
      Log.info { message }
      return log_closed_socket_and_exit if closed?

      enqueue_outbound(message.ends_with?(IRC_LINE_END) ? message : terminate_message(message))
    end

    def send_message(message : FastIRC::Message)
      line = String.build { |io| message.to_s(io) }
      Log.info { line }
      return log_closed_socket_and_exit if closed?

      enqueue_outbound(line)
    end

    def send_error(message)
      Log.info { "Sending ERROR to #{@nickname}: #{message}" }
      send_message(FastIRC::Message.new("ERROR", [message]))
    end

    def nickname=(new_nickname)
      @nickname = new_nickname
      set_hostmask
    end

    def send_message(prefix : String, command : String, *params)
      return log_closed_socket_and_exit if closed?
      message = Format.message(prefix, command, *params)
      Log.info { message }
      enqueue_outbound(message)
    end

    def send_message_now(prefix : String, command : String, *params)
      return log_closed_socket_and_exit if closed?
      message = Format.message(prefix, command, *params)
      Log.info { message }
      write_to_socket(message)
    end

    def complete_registration
      return if registered?
      return unless nickname && user
      if (server_password = Server.config.server_password) && password != server_password
        send_message(Server.clean_name, Numerics::ERR_PASSWDMISMATCH, nickname || "*", ":Password incorrect")
        return
      end

      apply_resolved_hostname
      if line = matching_line_ban
        reject_line_registration(line)
        return
      end

      self.registered = true
      Infrastructure::ServiceLocator.irc_service.sync_new_user(self)

      # Send welcome messages
      Server.welcome_message(self)
      send_message(Server.lusers(self))
      send_message(Server.motd(self))

      Log.info { "User #{nickname}!#{user} registered from #{host}" }
    end

    def close
      Log.info { "Closing connection" }
      close_outbound_queue
      socket.try(&.close)
      raise ClosedClient.new("closed")
    end

    def closed? : Bool
      socket.try(&.closed?) || false
    end

    def pong(params : Array(String))
      @last_pong = Time.utc
      @last_ping = @last_pong
      Log.debug { "PONG #{@nickname}" }
    end

    def ping(params : Array(String))
      send_message(create_pong_message(params))
      @last_pong = Time.utc
    end

    def send_heartbeat_ping(now : Time = Time.utc) : Nil
      return if closed?
      return if (last_ping = @last_ping) && now - last_ping < 20.seconds

      @last_ping = now
      send_message(create_ping_message)
    end

    def heartbeat_timed_out?(now : Time = Time.utc) : Bool
      return false unless last_ping = @last_ping
      return false if (last_pong = @last_pong) && last_pong >= last_ping

      now - last_ping > 1.minute
    end

    def each_channel(& : Domain::Channel ->) : Nil
      return unless nickname = self.nickname

      Infrastructure::ServiceLocator.channel_repository.each_user_channel(nickname) do |channel|
        yield channel
      end
    end

    def ban_match_context : Domain::BanMatchContext?
      return unless nick = nickname
      channel_repository = Infrastructure::ServiceLocator.channel_repository

      if domain_user = Infrastructure::ServiceLocator.user_repository[nick]?
        return domain_user.ban_match_context(@ip_address, channel_repository.find_user_channel_names(nick))
      end

      return unless current_user = user
      return unless current_hostmask = hostmask

      Domain::BanMatchContext.new(
        nick,
        current_user.name,
        @hostname,
        @ip_address,
        current_user.realname,
        current_hostmask,
        channel_repository.find_user_channel_names(nick)
      )
    end

    def shutdown
      return if @shutdown
      @shutdown = true

      if nickname = self.nickname
        channel_repository = Infrastructure::ServiceLocator.channel_repository
        affected_channels = channel_repository.remove_user_from_all_channels(nickname)
        notification_service = Infrastructure::ServiceLocator.notification_service
        hostmask = self.hostmask || nickname
        affected_channels.each do |channel_name|
          notification_service.notify_channel(channel_name, ":#{hostmask} PART #{channel_name}")
        end
        Infrastructure::ServiceLocator.user_repository.delete(nickname)
      end
      close_outbound_queue
      socket.try(&.close)
      Log.info { "#{@nickname} has disconnected" }
    end

    def update_activity
      @last_activity = Time.utc
    end

    private def run_commands(payload : FastIRC::Message)
      unless @rate_limiter.allow?(payload.command)
        send_message(Server.clean_name, Numerics::RPL_TRYAGAIN, nickname || "*", payload.command, ":Please wait a while and try again.")
        return
      end

      Performance::Metrics.increment_command(payload.command)

      case payload.command
      when "LIST", "WHOIS", "WHO", "NAMES", "LINKS", "STATS", "TIME", "VERSION", "ADMIN"
        handle_query_commands(payload)
      when "ISON", "USERHOST", "LUSERS", "MOTD"
        handle_simple_query(payload)
      when "NICK", "USER", "AWAY", "CAP", "PASS", "OPER"
        handle_user_commands(payload)
      when "PONG", "PING", "STARTTLS"
        handle_connection_commands(payload)
      when "JOIN", "PART", "MODE", "KICK", "TOPIC", "INVITE"
        handle_channel_commands(payload)
      when "QUIT", "NOTICE", "PRIVMSG"
        handle_message_commands(payload)
      when "KILL", "REHASH", "RESTART", "DIE", "CONNECT", "SQUIT",
           Domain::LineBan::KLINE, Domain::LineBan::GLINE, Domain::LineBan::ZLINE
        handle_operator_commands(payload)
      else
        # Unknown command
        send_message(Server.clean_name, Numerics::ERR_UNKNOWNCOMMAND, nickname || "*", payload.command, ":#{Utils::IrcUtils::ErrorMessages::UNKNOWN_COMMAND}")
      end
    end

    private def parse_message(line : String) : Nil
      run_commands(FastIRC.parse_line(line, strict: true))
    rescue ex : FastIRC::ParseException
      handle_parse_error(ex)
    end

    private def read_messages(io : IO) : Nil
      reader = FastIRC::Reader.new(io, strict: true)

      loop do
        begin
          break unless payload = reader.next
          run_commands(payload)
        rescue ex : FastIRC::ParseException
          handle_parse_error(ex)
          break if ex.message == "Line length longer than 8192 chars"
        end
      end
    end

    private def handle_parse_error(exception : FastIRC::ParseException) : Nil
      message = exception.message || "invalid IRC message"
      if message.includes?("maximum allowed size") || message.starts_with?("Line length longer")
        send_message(Server.clean_name, Numerics::ERR_INPUTTOOLONG, nickname || "*", ":Input line was too long")
      else
        Log.warn(exception: exception) { "Failed to parse IRC message" }
      end
    end

    private def handle_query_commands(payload : FastIRC::Message)
      return unless require_registered

      case payload.command
      when "LIST"
        Actions::List.call(self, payload.params.first?)
      when "WHOIS"
        handle_whois_command(payload)
      when "WHO"
        Actions::Who.call(self, payload.params.first?, payload.params[1]? == "o")
      when "NAMES"
        Actions::Names.call(self, payload.params.first?)
      when "LINKS"
        Commands::ServerCommands.links(self, payload.params)
      when "STATS"
        Commands::ServerCommands.stats(self, payload.params)
      when "TIME"
        Commands::ServerCommands.time(self, payload.params)
      when "VERSION"
        Commands::ServerCommands.version(self, payload.params)
      when "ADMIN"
        Commands::ServerCommands.admin(self, payload.params)
      end
    end

    private def handle_simple_query(payload : FastIRC::Message) : Nil
      return unless require_registered

      case payload.command
      when "ISON"     then handle_ison_command(payload)
      when "USERHOST" then handle_userhost_command(payload)
      when "LUSERS"   then send_message(Server.lusers(self))
      when "MOTD"     then send_message(Server.motd(self))
      end
    end

    private def handle_ison_command(payload : FastIRC::Message) : Nil
      return unless require_param_count(payload, 1, "ISON")

      online = String.build do |io|
        first = true
        payload.params.each do |requested_nickname|
          next unless user = Network::NetworkState.get_user(requested_nickname)

          io << ' ' unless first
          io << user.nickname
          first = false
        end
      end
      send_message(Server.clean_name, Numerics::RPL_ISON, nickname || "*", ":#{online}")
    end

    private def handle_userhost_command(payload : FastIRC::Message) : Nil
      return unless require_param_count(payload, 1, "USERHOST")

      reply = String.build do |io|
        first = true
        payload.params.each_with_index do |requested_nickname, index|
          break if index == 5
          next unless user = Network::NetworkState.get_user(requested_nickname)

          io << ' ' unless first
          io << user.nickname
          io << '*' if Domain::User::OPERATOR_MODES.any? { |mode| user.modes.includes?(mode) }
          io << '=' << (user.away_message ? '-' : '+') << user.username << '@' << user.hostname
          first = false
        end
      end
      send_message(Server.clean_name, Numerics::RPL_USERHOST, nickname || "*", ":#{reply}")
    end

    private def handle_whois_command(payload : FastIRC::Message) : Nil
      if payload.params.empty?
        send_message(Server.clean_name, Numerics::ERR_NONICKNAMEGIVEN, nickname || "*", ":No nickname given")
        return
      end

      Actions::Whois.call(self, payload.params.size > 1 ? payload.params[1] : payload.params.first)
    end

    private def handle_user_commands(payload : FastIRC::Message)
      case payload.command
      when "PASS"
        handle_pass_command(payload)
      when "NICK"
        handle_nick_command(payload)
      when "USER"
        handle_user_command(payload)
      when "AWAY"
        return unless require_registered
        away_message = payload.params.empty? ? nil : Utils::IrcUtils.trailing_param(payload.params, 0)
        Actions::Away.call(self, away_message)
      when "CAP"
        return if payload.params.empty?
        Actions::Cap.call(self, payload.params.first, payload.params[1]?)
      when "OPER"
        return unless require_registered
        handle_oper_command(payload)
      end
    end

    private def handle_pass_command(payload : FastIRC::Message) : Nil
      if registered?
        send_message(Server.clean_name, Numerics::ERR_ALREADYREGISTRED, nickname || "*", ":You may not reregister")
        return
      end
      unless require_param_count(payload, 1, "PASS", "*")
        return
      end

      self.password = payload.params.first
      return unless server_password = Server.config.server_password
      if password == server_password
        complete_registration
        return
      end

      send_message(Server.clean_name, Numerics::ERR_PASSWDMISMATCH, "*", ":Password incorrect")
      close
    end

    private def handle_nick_command(payload : FastIRC::Message) : Nil
      if payload.params.empty?
        send_message(Server.clean_name, Numerics::ERR_NONICKNAMEGIVEN, nickname || "*", ":No nickname given")
        return
      end

      if payload.params.size != 1
        send_message(Server.clean_name, Numerics::ERR_ERRONEUSNICKNAME, payload.params.first? || "*", ":Erroneous nickname")
        return
      end

      Actions::Nick.call(self, payload.params.first)
    end

    private def handle_oper_command(payload : FastIRC::Message) : Nil
      return unless require_param_count(payload, 2, "OPER")

      Infrastructure::ServiceLocator.irc_service.oper(self, payload.params[0], payload.params[1])
    end

    private def handle_user_command(payload : FastIRC::Message) : Nil
      if registered?
        send_message(Server.clean_name, Numerics::ERR_ALREADYREGISTRED, nickname || "*", ":You may not reregister")
        return
      end

      return unless require_param_count(payload, 4, "USER", "*")

      self.user = payload.params
    end

    private def handle_connection_commands(payload : FastIRC::Message)
      case payload.command
      when "PONG"
        return send_no_origin if payload.params.empty?
        pong(payload.params)
      when "PING"
        return send_no_origin if payload.params.empty?
        ping(payload.params)
      when "STARTTLS"
        Actions::Starttls.call(self)
      end
    end

    private def handle_channel_commands(payload : FastIRC::Message)
      return unless require_registered

      case payload.command
      when "JOIN"
        handle_join_command(payload)
      when "PART"
        handle_part_command(payload)
      when "MODE"
        return unless require_param_count(payload, 1, "MODE")
        Actions::Mode.call(self, payload.params)
      when "KICK"
        handle_kick_command(payload)
      when "TOPIC"
        handle_topic_command(payload)
      when "INVITE"
        handle_invite_command(payload)
      end
    end

    private def handle_join_command(payload : FastIRC::Message) : Nil
      return unless require_param_count(payload, 1, "JOIN")

      channel_param = payload.params.first
      if channel_param == "0"
        if nickname = self.nickname
          channel_repository = Infrastructure::ServiceLocator.channel_repository
          channel_repository.find_user_channels(nickname).each do |channel|
            Actions::Part.call(self, channel.name)
          end
        end
        return
      end

      keys = Utils::IrcUtils.split_list_param(payload.params[1]?)
      index = 0
      Utils::IrcUtils.each_list_param(channel_param) do |channel_name|
        Actions::Join.call(self, channel_name, keys[index]?)
        index += 1
      end
    end

    private def handle_part_command(payload : FastIRC::Message) : Nil
      return unless require_param_count(payload, 1, "PART")

      reason = payload.params.size > 1 ? payload.params[1].lchop(':') : nil
      Utils::IrcUtils.each_list_param(payload.params.first) do |channel_name|
        Actions::Part.call(self, channel_name, reason)
      end
    end

    private def handle_kick_command(payload : FastIRC::Message) : Nil
      return unless require_param_count(payload, 2, "KICK")

      Actions::Kick.call(self, payload.params)
    end

    private def handle_topic_command(payload : FastIRC::Message) : Nil
      return unless require_param_count(payload, 1, "TOPIC")

      Actions::Topic.call(self, payload.params)
    end

    private def handle_invite_command(payload : FastIRC::Message) : Nil
      return unless require_param_count(payload, 2, "INVITE")

      invited_user = payload.params.first
      channel_name = payload.params[1]
      Actions::Invite.call(self, invited_user, channel_name)
    end

    private def require_param_count(payload : FastIRC::Message, minimum : Int32, command : String, target : String = nickname || "*") : Bool
      return true if payload.params.size >= minimum

      send_message(Server.clean_name, Numerics::ERR_NEEDMOREPARAMS, target, command, ":Not enough parameters")
      false
    end

    private def handle_message_commands(payload : FastIRC::Message)
      case payload.command
      when "QUIT"
        reason = payload.params.empty? ? nickname : Utils::IrcUtils.trailing_param(payload.params, 0)
        Actions::Quit.call(self, reason)
        quit(reason)
      when "NOTICE"
        return unless require_registered
        return if payload.params.size < 2
        target = payload.params.first
        message = Utils::IrcUtils.trailing_param(payload.params, 1)
        Actions::Notice.call(self, target, message)
      when "PRIVMSG"
        handle_privmsg_command(payload)
      end
    end

    private def handle_privmsg_command(payload : FastIRC::Message) : Nil
      return unless require_registered
      if payload.params.empty?
        send_message(Server.clean_name, Numerics::ERR_NORECIPIENT, nickname || "*", ":No recipient given (PRIVMSG)")
        return
      end
      if payload.params.size < 2 || payload.params[1].empty?
        send_message(Server.clean_name, Numerics::ERR_NOTEXTTOSEND, nickname || "*", ":No text to send")
        return
      end

      Actions::Privmsg.call(self, payload.params.first, Utils::IrcUtils.trailing_param(payload.params, 1))
    end

    private def handle_operator_commands(payload : FastIRC::Message)
      return unless require_registered

      irc_service = Infrastructure::ServiceLocator.irc_service

      case payload.command
      when "KILL"
        return unless require_param_count(payload, 2, "KILL")

        irc_service.kill_user(self, payload.params.first, Utils::IrcUtils.trailing_param(payload.params, 1))
      when "REHASH"
        irc_service.rehash(self)
      when "RESTART"
        reason = payload.params.empty? ? "Restart requested" : Utils::IrcUtils.trailing_param(payload.params, 0)
        irc_service.restart(self, reason)
      when "DIE"
        reason = payload.params.empty? ? "Shutdown requested" : Utils::IrcUtils.trailing_param(payload.params, 0)
        irc_service.die(self, reason)
      when "CONNECT"
        return unless require_param_count(payload, 1, "CONNECT")

        irc_service.connect_server(self, payload.params.first, payload.params[1]?.try(&.to_i?), payload.params[2]?)
      when "SQUIT"
        return unless require_param_count(payload, 2, "SQUIT")

        irc_service.squit_server(self, payload.params.first, Utils::IrcUtils.trailing_param(payload.params, 1))
      when Domain::LineBan::KLINE, Domain::LineBan::GLINE, Domain::LineBan::ZLINE
        return unless require_param_count(payload, 1, payload.command)

        irc_service.line_ban(self, payload.command, payload.params)
      end
    end

    private def require_registered : Bool
      return true if registered?

      Utils::IrcUtils.send_not_registered_error(self)
      false
    end

    private def send_no_origin : Nil
      send_message(Server.clean_name, Numerics::ERR_NOORIGIN, nickname || "*", ":No origin specified")
    end

    private def remote_ip_address(socket : Network::SSLSocket::IRCSocket?) : String
      case socket
      when TCPSocket
        socket.remote_address.address
      else
        "127.0.0.1"
      end
    end

    private def initial_hostname(socket : Network::SSLSocket::IRCSocket?) : String
      if sock = socket
        Hostname.get_hostname(sock)
      else
        "localhost"
      end
    end

    private def start_hostname_lookup(ip_address : String) : Channel(String?)?
      Infrastructure::ServiceLocator.dns_resolver_service?.try(&.resolve_async(ip_address))
    end

    private def remove_registered_client : Nil
      return unless nick = nickname
      return if nick.empty?

      Infrastructure::ServiceLocator.user_repository.delete(nick)
    end

    private def cleanup_after_disconnect : Nil
      return if @shutdown
      @shutdown = true

      if nick = nickname
        channel_repository = Infrastructure::ServiceLocator.channel_repository
        user_channels = channel_repository.find_user_channels(nick)
        quit_message = String.build do |io|
          io << ':' << (hostmask || nick) << " QUIT :Client disconnected"
        end

        Infrastructure::ServiceLocator.user_repository.delete(nick)
        channel_repository.remove_user_from_all_channels(nick)
        Infrastructure::ServiceLocator.notification_service.notify_channels(nick, user_channels, quit_message)
      end

      close_outbound_queue
      socket.try(&.close)
      Log.info { "#{@nickname} has disconnected" }
    end

    private def apply_resolved_hostname : Nil
      lookup = @hostname_lookup
      return unless lookup

      dns_resolver = Infrastructure::ServiceLocator.dns_resolver_service
      return unless resolved_hostname = dns_resolver.receive_result(lookup)

      @hostname = resolved_hostname
      set_hostmask
      update_domain_user_hostname(resolved_hostname)
    ensure
      @hostname_lookup = nil
    end

    private def update_domain_user_hostname(hostname : String) : Nil
      return unless nick = nickname
      return unless domain_user = Infrastructure::ServiceLocator.user_repository[nick]?

      domain_user.hostname = hostname
      Infrastructure::ServiceLocator.user_repository[nick] = domain_user
    end

    private def matching_line_ban : Domain::LineBan?
      return unless context = ban_match_context

      Network::LineState.matching(context)
    end

    private def reject_line_registration(line : Domain::LineBan) : Nil
      target = nickname || "*"
      send_message(Server.clean_name, Numerics::ERR_YOUREBANNEDCREEP, target, ":You are banned from this server (#{line.reason})")
      send_error("Banned: #{line.reason}")
      shutdown
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

    private def enqueue_outbound(message : String) : Bool
      return write_to_socket(message) if @direct_writes
      return false if @outbound_messages.closed?

      select
      when @outbound_messages.send(message)
        true
      else
        close_slow_client
        false
      end
    rescue Channel::ClosedError
      false
    end

    private def close_outbound_queue : Nil
      @outbound_messages.close
    end

    private def create_ping_message : FastIRC::Message
      FastIRC::Message.new("PING", ["#{nickname || Server.name} #{Server.clean_name}"])
    end

    private def create_pong_message(params : Array(String)) : FastIRC::Message
      prefix = FastIRC::Prefix.new(source: Server.name, user: nil, host: nil)
      FastIRC::Message.new("PONG", params, prefix: prefix)
    end

    private def terminate_message(message : String) : String
      String.build(capacity: message.bytesize + IRC_LINE_END.bytesize) do |io|
        io << message << IRC_LINE_END
      end
    end

    private def write_to_socket(message : String) : Bool
      return false unless current_socket = socket

      @socket_write_mutex.synchronize do
        current_socket << message
        current_socket.flush
      end
      true
    rescue ex : IO::Error | IO::TimeoutError
      close_socket_after_write_error(ex)
      false
    end

    private def close_socket_after_write_error(exception : Exception) : Nil
      Log.debug(exception: exception) { "Closing client socket after write failure" }
      socket.try(&.close)
    rescue ex : IO::Error
      Log.debug(exception: ex) { "Failed to close client socket after write failure" }
    end

    private def close_slow_client : Nil
      return if @shutdown

      Log.debug { "Closing #{@nickname || @host || "unknown"} because outbound queue is full" }
      spawn cleanup_after_disconnect
    rescue ex : IO::Error
      Log.debug(exception: ex) { "Failed to close slow client socket" }
    end

    private def get_hostmask : String?
      if (nick = nickname) && (domain_user = Infrastructure::ServiceLocator.user_repository[nick]?)
        return domain_user.hostmask
      end

      nick = nickname || ""
      username = user.try(&.name) || ""
      Utils::IrcUtils.format_hostmask(nick, username, @hostname)
    end

    private def log_closed_socket_and_exit
      Log.debug { "Socket is closed, can't send message" }
    end

    private def register_domain_user(nickname : String, username : String, realname : String, user_mode : String)
      domain_user = Domain::User.new(
        nickname,
        username,
        @hostname,
        realname,
        Server.name
      )
      apply_registration_user_modes(domain_user, user_mode)
      Infrastructure::ServiceLocator.user_repository[nickname] = domain_user
      set_hostmask
    end

    private def apply_registration_user_modes(domain_user : Domain::User, user_mode : String) : Nil
      mode_value = user_mode.to_i? || 0
      domain_user.modes << 'w' if (mode_value & 4) != 0
      domain_user.modes << 'i' if (mode_value & 8) != 0
    end
  end
end
