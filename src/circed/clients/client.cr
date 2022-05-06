require "tasker"

module Circed
  class Client

    getter socket : TCPSocket?
    getter host : String?
    getter nickname : String?

    getter user : User?

    @pingpong : Pingpong?

    def initialize(@socket : Socket?)
      @host = @socket.try(&.remote_address.to_s)
    end

    def setup
      message_handling
    end

    def message_handling
      return unless socket
      while !socket.not_nil!.closed?
        FastIRC.parse(socket.not_nil!) do |payload|
          case payload.command
          when "NICK"
            set_nickname(payload.params.first)
          when "USER"
            set_user(payload.params)
          when "PONG"
            pong(payload.params)
          when "PING"
            ping(payload.params)
          when "JOIN"
            next if payload.params.empty?
            join_channel(payload.params.first)
          when "PART"
            part_channel(payload.params.first)
          when "MODE"
            mode(payload.params)
          when "QUIT"
            quit(payload.params)
          when "KICK"
            kick(payload.params)
          when "TOPIC"
            topic(payload.params)
          when "INVITE"
            invite(payload.params)
          when "NOTICE"
            notice(payload.params)
          when "PRIVMSG"
            private_message(payload.params.first, payload.params)
          end
        end

        if closed?
          UserHandler.remove_connection(nickname.to_s) unless nickname.to_s.empty?
          break
        end
      end
    rescue e : IO::Error
      shutdown
      UserHandler.remove_connection(nickname.to_s) unless nickname.to_s.empty?
    rescue e : Circed::ClosedClient
      UserHandler.remove_connection(nickname.to_s) unless nickname.to_s.empty?
    rescue e : Exception
      shutdown
      UserHandler.remove_connection(nickname.to_s) unless nickname.to_s.empty?
    end

    def set_nickname(new_nickname)
      Actions::Nick.call(self, new_nickname)
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

    def private_message(receiver : String, message : Array(String))
      Actions::Privmsg.call(self, receiver, message)
    end

    def join_channel(channel : String)
      Actions::Join.call(self, channel)
    end

    def part_channel(channel : String)
      Actions::Part.call(self, channel)
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

    def mode(message)
      Actions::Mode.call(self, message)
    end

    def nickname=(new_nickname)
      @nickname = new_nickname
    end

    def topic(message)
      Actions::Topic.call(self, message)
    end

    def kick(message)
      Actions::Kick.call(self, message)
    end

    def invite(message)
      invited_user = message.first
      Actions::Invite.call(self, invited_user, message)
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
      #send_message("PING :#{@nickname} :localhost")
    end

    def ping(params : Array(String))
      @pingpong.try(&.ping(params))
      #return if @last_checked && @last_checked.not_nil! < 5.seconds.ago
    end

    def shutdown
      ChannelHandler.remove_user_from_all_channels(self)
      if @pingpong
        @pingpong.try(&.stop_ping)
        @pingpong.try(&.stop_pong_check)
      end
      socket.try(&.close)
    end
  end
end
