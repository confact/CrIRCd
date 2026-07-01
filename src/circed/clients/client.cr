require "tasker"
require "../network/ssl_socket"
require "../actions/starttls"

module Circed
  class Client
    property socket : Network::SSLSocket::IRCSocket? = nil
    getter host : String?
    getter nickname : String?
    getter hostmask : String?
    property last_activity : Time
    getter signon_time : Time

    getter user : User?
    property? registered : Bool = false
    property password : String?

    @pingpong : Pingpong?

    @buffer : Array(String) = [] of String
    @shutdown : Bool = false

    def initialize(@socket : Network::SSLSocket::IRCSocket?, buffer)
      @buffer = buffer
      @host = if sock = @socket
                case sock
                when TCPSocket
                  sock.remote_address.to_s
                else
                  "ssl_client"
                end
              end
      set_hostmask
      @last_activity = Time.utc
      @signon_time = Time.utc
    end

    def setup
      message_handling
    end

    def message_handling
      return unless socket

      # go through buffer first
      @buffer.each do |buff|
        begin
          payload = FastIRC.parse_line(buff)
          run_commands(payload)
        rescue ex
          Log.warn { "Failed to parse IRC line: #{buff} - #{ex.message}" }
        end
      end

      if current_socket = socket
        while !current_socket.closed?
          FastIRC.parse(current_socket) do |payload|
            run_commands(payload)
          end

          if closed?
            user_repository = Infrastructure::ServiceLocator.user_repository
            user_repository.remove_client(nickname.to_s) unless nickname.to_s.empty?
            break
          end
        end
      end
    rescue e : IO::Error
      Log.warn(exception: e) { "IO Error" }
      shutdown
      user_repository = Infrastructure::ServiceLocator.user_repository
      user_repository.remove_client(nickname.to_s) unless nickname.to_s.empty?
    rescue e : Circed::ClosedClient
      user_repository = Infrastructure::ServiceLocator.user_repository
      user_repository.remove_client(nickname.to_s) unless nickname.to_s.empty?
    rescue e : Exception
      Log.error(exception: e) { "Error" }
      shutdown
      user_repository = Infrastructure::ServiceLocator.user_repository
      user_repository.remove_client(nickname.to_s) unless nickname.to_s.empty?
    end

    def user=(users_messages : Array(String))
      mode = users_messages[1]
      username = users_messages.first
      realname = users_messages[3].sub(":", "")
      @user = User.new(self, mode, username, realname)
      set_hostmask
      Log.debug { "Set user to: #{user}" }

      # Create domain user in repository if we have a nickname
      if nickname = @nickname
        register_domain_user(nickname, username, realname)
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

      write_to_socket(message + "\n")
    end

    def send_error(message)
      Log.info { "Sending ERROR to #{@nickname}: #{message}" }
      return if closed?
      write_to_socket("ERROR :#{message}\n")
    end

    def notice(message)
      send_message(":#{message}")
    end

    def nickname=(new_nickname)
      @nickname = new_nickname
      set_hostmask
    end

    def send_message(prefix, command, *params)
      return log_closed_socket_and_exit if closed?
      message = "#{prefix} #{command} #{params.join(" ")}\n"
      Log.info { message }
      write_to_socket(message)
    end

    def send_message_to_receiver(command, sender_nickname, sender_user, sender_host, params : Array(String))
      if current_user = user
        send_message_common(command, sender_nickname, sender_user, sender_host, [current_user.name] + params)
      end
    end

    def send_message_to_server(command, sender_nickname, sender_user, sender_host, params : Array(String))
      send_message_common(command, sender_nickname, sender_user, sender_host, params)
    end

    def send_message_common(command, sender_nickname, sender_user, sender_host, params : Array(String))
      current_socket = socket
      return unless current_socket

      update_activity
      prefix = FastIRC::Prefix.new(source: sender_nickname, user: sender_user, host: sender_host)
      begin
        FastIRC::Message.new(command, params, prefix: prefix).to_s(current_socket)
        Log.debug { "sending message to #{sender_nickname}" }
        log_closed_socket_and_exit if closed?
        current_socket.flush
      rescue ex : IO::Error | IO::TimeoutError
        close_socket_after_write_error(ex)
      end
    end

    def complete_registration
      return if registered?
      return unless nickname && user

      self.registered = true

      # Send welcome messages
      Server.welcome_message(self)

      # Send MOTD and LUSERS
      Server.lusers(self)
      Server.motd(self)

      @pingpong = Pingpong.new(self)

      Log.info { "User #{nickname}!#{user} registered from #{host}" }
    end

    def close
      Log.info { "Closing connection" }
      socket.try(&.close)
      raise ClosedClient.new("closed")
    end

    def closed? : Bool
      socket.try(&.closed?) || false
    end

    def pong(params : Array(String))
      @pingpong.try(&.pong(params))
      Log.debug { "PONG #{@nickname}" }
      # send_message("PING :#{@nickname} :localhost")
    end

    def ping(params : Array(String))
      @pingpong.try(&.ping(params))
      # return if @last_checked && @last_checked.not_nil! < 5.seconds.ago
    end

    def channels
      return [] of Domain::Channel unless nickname = self.nickname
      channel_repository = Infrastructure::ServiceLocator.channel_repository
      channel_repository.find_user_channels(nickname)
    end

    def ban_match_context : Domain::BanMatchContext?
      return unless nick = nickname
      channel_repository = Infrastructure::ServiceLocator.channel_repository

      if domain_user = Infrastructure::ServiceLocator.user_repository.get(nick)
        return Domain::BanMatchContext.new(
          domain_user.nickname,
          domain_user.username,
          domain_user.hostname,
          domain_user.realname,
          domain_user.hostmask,
          channel_repository.find_user_channel_names(nick)
        )
      end

      return unless current_user = user
      return unless current_hostmask = hostmask

      Domain::BanMatchContext.new(
        nick,
        current_user.name,
        get_hostname || @host || "localhost",
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
        affected_channels.each do |channel_name|
          notification_service.notify_user_parted(nickname, channel_name)
        end
      end
      if @pingpong
        @pingpong.try(&.stop_ping)
        @pingpong.try(&.stop_pong_check)
      end
      socket.try(&.close)
      Log.info { "#{@nickname} has disconnected" }
    end

    def update_activity
      @last_activity = Time.utc
    end

    private def run_commands(payload : FastIRC::Message)
      Performance::Metrics.increment_command(payload.command)

      case payload.command
      when "LIST", "WHOIS", "WHO", "NAMES", "LINKS", "STATS", "TIME", "VERSION", "ADMIN"
        handle_query_commands(payload)
      when "NICK", "USER", "AWAY", "CAP", "PASS"
        handle_user_commands(payload)
      when "PONG", "PING", "STARTTLS"
        handle_connection_commands(payload)
      when "JOIN", "PART", "MODE", "KICK", "TOPIC", "INVITE"
        handle_channel_commands(payload)
      when "QUIT", "NOTICE", "PRIVMSG"
        handle_message_commands(payload)
      else
        # Unknown command
        send_message(Server.clean_name, Numerics::ERR_UNKNOWNCOMMAND, nickname || "*", payload.command, ":#{Utils::IrcUtils::ErrorMessages::UNKNOWN_COMMAND}")
      end
    end

    private def handle_query_commands(payload : FastIRC::Message)
      case payload.command
      when "LIST"
        Actions::List.call(self)
      when "WHOIS"
        Actions::Whois.call(self, payload.params.first) unless payload.params.empty?
      when "WHO"
        Actions::Who.call(self, payload.params.first) unless payload.params.empty?
      when "NAMES"
        Actions::Names.call(self, payload.params.first) unless payload.params.empty?
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

    private def handle_user_commands(payload : FastIRC::Message)
      case payload.command
      when "PASS"
        if payload.params.empty?
          send_message(Server.clean_name, Numerics::ERR_NEEDMOREPARAMS, "*", "PASS", ":Not enough parameters")
          return
        end
        self.password = payload.params.first

        # Check if password matches server password (if configured)
        if server_password = Server.config.server_password
          if password != server_password
            send_message(Server.clean_name, Numerics::ERR_PASSWDMISMATCH, "*", ":Password incorrect")
            close
            return
          end
        end
      when "NICK"
        if payload.params.size != 1
          # Invalid nickname format (e.g., contains spaces or missing param)
          send_message(Server.clean_name, Numerics::ERR_ERRONEUSNICKNAME, payload.params.first? || "*", ":Erroneous nickname")
          return
        end
        Actions::Nick.call(self, payload.params.first)
      when "USER"
        if payload.params.size < 4
          send_message(Server.clean_name, Numerics::ERR_NEEDMOREPARAMS, "*", "USER", ":Not enough parameters")
          return
        end
        self.user = payload.params
      when "AWAY"
        away_message = payload.params.empty? ? nil : payload.params.join(" ")
        Actions::Away.call(self, away_message)
      when "CAP"
        return if payload.params.empty?
        Actions::Cap.call(self, payload.params)
      end
    end

    private def handle_connection_commands(payload : FastIRC::Message)
      case payload.command
      when "PONG"
        pong(payload.params)
      when "PING"
        ping(payload.params)
      when "STARTTLS"
        Actions::Starttls.call(self)
      end
    end

    private def handle_channel_commands(payload : FastIRC::Message)
      # Require registration before channel commands
      unless nickname && user
        send_message(Server.clean_name, Numerics::ERR_NOTREGISTERED, nickname || "*", ":You have not registered")
        return
      end
      case payload.command
      when "JOIN"
        if payload.params.empty?
          # Need more params
          send_message(Server.clean_name, Numerics::ERR_NEEDMOREPARAMS, nickname || "*", "JOIN", ":Not enough parameters")
          return
        end
        Actions::Join.call(self, payload.params.first)
      when "PART"
        if payload.params.empty?
          send_message(Server.clean_name, Numerics::ERR_NEEDMOREPARAMS, nickname || "*", "PART", ":Not enough parameters")
          return
        end
        channel_name = payload.params.first
        reason = payload.params.size > 1 ? payload.params[1].lchop(':') : nil
        Actions::Part.call(self, channel_name, reason)
      when "MODE"
        Actions::Mode.call(self, payload.params)
      when "KICK"
        if payload.params.size < 2
          send_message(Server.clean_name, Numerics::ERR_NEEDMOREPARAMS, nickname || "*", "KICK", ":Not enough parameters")
          return
        end
        Actions::Kick.call(self, payload.params)
      when "TOPIC"
        if payload.params.empty?
          send_message(Server.clean_name, Numerics::ERR_NEEDMOREPARAMS, nickname || "*", "TOPIC", ":Not enough parameters")
          return
        end
        Actions::Topic.call(self, payload.params)
      when "INVITE"
        if payload.params.size < 2
          send_message(Server.clean_name, Numerics::ERR_NEEDMOREPARAMS, nickname || "*", "INVITE", ":Not enough parameters")
          return
        end
        invited_user = payload.params.first
        channel_name = payload.params[1]
        Actions::Invite.call(self, invited_user, channel_name)
      end
    end

    private def handle_message_commands(payload : FastIRC::Message)
      case payload.command
      when "QUIT"
        Actions::Quit.call(self, payload.params.join(" ")) unless payload.params.empty?
        quit(payload.params)
      when "NOTICE"
        if payload.params.size < 2
          send_message(Server.clean_name, Numerics::ERR_NEEDMOREPARAMS, nickname || "*", "NOTICE", ":Not enough parameters")
          return
        end
        target = payload.params.first
        message = payload.params[1..-1].join(" ")
        Actions::Notice.call(self, target, message)
      when "PRIVMSG"
        if payload.params.size < 2
          send_message(Server.clean_name, Numerics::ERR_NEEDMOREPARAMS, nickname || "*", "PRIVMSG", ":Not enough parameters")
          return
        end
        target = payload.params.first
        message = payload.params[1..-1].join(" ")
        Actions::Privmsg.call(self, target, message)
      end
    end

    private def get_hostname : String?
      current_socket = socket
      return "localhost" unless current_socket
      Hostname.get_hostname(current_socket) || "localhost"
    end

    private def write_to_socket(message : String) : Bool
      return false unless current_socket = socket

      current_socket << message
      current_socket.flush
      true
    rescue ex : IO::Error | IO::TimeoutError
      close_socket_after_write_error(ex)
      false
    end

    private def close_socket_after_write_error(exception : Exception) : Nil
      Log.debug(exception: exception) { "Closing client socket after write failure" }
      socket.try(&.close)
    rescue close_exception : IO::Error
      Log.debug(exception: close_exception) { "Failed to close client socket after write failure" }
    end

    private def get_hostmask : String?
      if (nick = nickname) && (domain_user = Infrastructure::ServiceLocator.user_repository.get(nick))
        return domain_user.hostmask
      end

      nick = nickname || ""
      username = user.try(&.name) || ""
      hostname = get_hostname || "localhost"
      Utils::IrcUtils.format_hostmask(nick, username, hostname)
    end

    private def log_closed_socket_and_exit
      Log.debug { "Socket is closed, can't send message" }
    end

    private def register_domain_user(nickname : String, username : String, realname : String)
      hostname = get_hostname || @host || "localhost"
      domain_user = Domain::User.new(
        nickname,
        username,
        hostname,
        realname,
        Server.name
      )
      Infrastructure::ServiceLocator.user_repository.add(nickname, domain_user)
      set_hostmask
    end
  end
end
