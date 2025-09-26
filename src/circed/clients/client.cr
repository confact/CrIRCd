require "tasker"

module Circed
  class Client
    getter socket : IPSocket? = nil
    getter host : String?
    getter nickname : String?
    getter hostmask : String?
    property last_activity : Time
    getter signon_time : Time

    getter user : User?

    @pingpong : Pingpong?

    @buffer : Array(String) = [] of String

    def initialize(@socket : IPSocket?, buffer)
      @buffer = buffer
      if @socket.is_a?(TCPSocket)
        @host = @socket.try(&.remote_address.to_s)
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
      Log.debug { "Set user to: #{user}" }
      Circed::Server.welcome_message(self)
      @pingpong = Pingpong.new(self)
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

      socket.try(&.puts(message + "\n"))
    end

    def send_error(message)
      Log.info { "Sending ERROR to #{@nickname}: #{message}" }
      return if closed?
      socket.try(&.puts("ERROR :#{message}\n"))
    end

    def notice(message)
      send_message(":#{message}")
    end

    def nickname=(new_nickname)
      @nickname = new_nickname
    end

    def send_message(prefix, command, *params)
      return log_closed_socket_and_exit if closed?
      message = "#{prefix} #{command} #{params.join(" ")}\n"
      Log.info { message }
      socket.try(&.puts(message))
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
      FastIRC::Message.new(command, params, prefix: prefix).to_s(current_socket)
      Log.debug { "sending message to #{sender_nickname}" }
      log_closed_socket_and_exit if closed?
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

    def shutdown
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
      case payload.command
      when "LIST", "WHOIS", "WHO", "NAMES"
        handle_query_commands(payload)
      when "NICK", "USER", "AWAY", "CAP"
        handle_user_commands(payload)
      when "PONG", "PING"
        handle_connection_commands(payload)
      when "JOIN", "PART", "MODE", "KICK", "TOPIC", "INVITE"
        handle_channel_commands(payload)
      when "QUIT", "NOTICE", "PRIVMSG"
        handle_message_commands(payload)
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
      end
    end

    private def handle_user_commands(payload : FastIRC::Message)
      case payload.command
      when "NICK"
        Actions::Nick.call(self, payload.params.first) unless payload.params.empty?
      when "USER"
        self.user = payload.params
      when "AWAY"
        Actions::Away.call(self, payload.params.join(" ")) unless payload.params.empty?
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
      end
    end

    private def handle_channel_commands(payload : FastIRC::Message)
      case payload.command
      when "JOIN"
        return if payload.params.empty?
        Actions::Join.call(self, payload.params.first)
      when "PART"
        Actions::Part.call(self, payload.params.first)
      when "MODE"
        Actions::Mode.call(self, payload.params)
      when "KICK"
        Actions::Kick.call(self, payload.params)
      when "TOPIC"
        Actions::Topic.call(self, payload.params)
      when "INVITE"
        return if payload.params.size < 2
        invited_user = payload.params.first
        Actions::Invite.call(self, invited_user, payload.params)
      end
    end

    private def handle_message_commands(payload : FastIRC::Message)
      case payload.command
      when "QUIT"
        Actions::Quit.call(self, payload.params.join(" ")) unless payload.params.empty?
        quit(payload.params)
      when "NOTICE"
        notice(payload.params)
      when "PRIVMSG"
        Actions::Privmsg.call(self, payload.params.first, payload.params)
      end
    end

    private def get_hostname : String?
      current_socket = socket
      return "localhost" unless current_socket
      Hostname.get_hostname(current_socket) || "localhost"
    end

    private def get_hostmask : String?
      hostname = get_hostname
      "#{nickname}!#{user.try(&.name)}@#{hostname}"
    end

    private def log_closed_socket_and_exit
      Log.debug { "Socket is closed, can't send message" }
    end
  end
end
