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

    def initialize(@socket : IPSocket?)
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
      while !socket.not_nil!.closed?
        FastIRC.parse(socket.not_nil!) do |payload|
          case payload.command
          when Actions::List::COMMAND
            Actions::List.call(self)
          when Actions::Whois::COMMAND
            Actions::Whois.call(self, payload.params.first)
          when Actions::Nick::COMMAND
            Actions::Nick.call(self, payload.params.first)
          when "USER"
            set_user(payload.params)
          when "PONG"
            pong(payload.params)
          when "PING"
            ping(payload.params)
          when Actions::Join::COMMAND
            next if payload.params.empty?
            Actions::Join.call(self, payload.params.first)
          when Actions::Part::COMMAND
            Actions::Part.call(self, payload.params.first)
          when Actions::Mode::COMMAND
            Actions::Mode.call(self, payload.params)
          when "QUIT"
            quit(payload.params)
          when Actions::Kick::COMMAND
            Actions::Kick.call(self, payload.params)
          when Actions::Topic::COMMAND
            Actions::Topic.call(self, payload.params)
          when Actions::Invite::COMMAND
            invited_user = payload.params.first
            Actions::Invite.call(self, invited_user, payload.params)
          when "NOTICE"
            notice(payload.params)
          when Actions::Privmsg::COMMAND
            Actions::Privmsg.call(self, payload.params.first, payload.params)
          end
        end

        if closed?
          UserHandler.remove_connection(nickname.to_s) unless nickname.to_s.empty?
          break
        end
      end
    rescue e : IO::Error
      Log.warn(exception: e) { "IO Error" }
      shutdown
      UserHandler.remove_connection(nickname.to_s) unless nickname.to_s.empty?
    rescue e : Circed::ClosedClient
      UserHandler.remove_connection(nickname.to_s) unless nickname.to_s.empty?
    rescue e : Exception
      Log.error(exception: e) { "Error" }
      shutdown
      UserHandler.remove_connection(nickname.to_s) unless nickname.to_s.empty?
    end

    def set_user(users_messages : Array(String))
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
      if closed?
        Log.debug { "Socket is closed, can't send message" }
        return
      end
      socket.try(&.puts(message + "\n"))
    end

    def notice(message)
      send_message(":#{message}")
    end

    def nickname=(new_nickname)
      @nickname = new_nickname
    end

    def send_message(prefix, command, *params)
      if closed?
        Log.debug { "Socket is closed, can't send message" }
        return
      end
      message = "#{prefix} #{command} #{params.join(" ")}\n"
      Log.info { message }
      socket.try(&.puts(message))
    end

    def send_message_to_receiver(command, sender_nickname, sender_user, sender_host, params : Array(String))
      return unless socket
      update_activity
      prefix = FastIRC::Prefix.new(source: sender_nickname, user: sender_user, host: sender_host)
      FastIRC::Message.new(command, [user.not_nil!.name] + params, prefix: prefix).to_s(socket.not_nil!)
      Log.debug { "sending message to #{sender_nickname}" }
      if closed?
        Log.debug { "Socket is closed, can't send message" }
        return
      end
    end

    def send_message_to_server(command, sender_nickname, sender_user, sender_host, params : Array(String))
      return unless socket
      update_activity
      prefix = FastIRC::Prefix.new(source: sender_nickname, user: sender_user, host: sender_host)
      FastIRC::Message.new(command, params, prefix: prefix).to_s(socket.not_nil!)
      Log.debug { "sending message to #{sender_nickname}" }
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
      ChannelHandler.user_channels(self)
    end

    def shutdown
      ChannelHandler.remove_user_from_all_channels(self)
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

    private def get_hostname : String?
      Hostname.get_hostname(socket.not_nil!) || "localhost"
    end

    private def get_hostmask : String?
      hostname = get_hostname
      "#{nickname}!#{user.try(&.name)}@#{hostname}"
    end

  end
end
