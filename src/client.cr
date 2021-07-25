require "tasker"

module Circed
  class Client
    include Pinger

    getter socket : TCPSocket
    getter nickname : String?
    getter mode : String?
    getter user : String?
    getter realname : String?

    @last_checked : Time?
    @last_answered : Time?

    @task_ping : Tasker::Repeat(Int32) | Tasker::Repeat(Nil) | Nil
    @task_pong_check : Tasker::Repeat(Int32) | Tasker::Repeat(Nil) | Nil

    def initialize(@socket : Socket)
    end

    def setup
      message_handling
    end

    def message_handling
      while message = socket.gets
        break if socket.closed?
        Log.debug { "got this message: #{message} " }
        payload = Payload.parse_message(message.to_s)

        Log.info { "message: #{payload.inspect} " }
        return if payload.nil?

        case payload.message_type
        when "NICK"
          set_nickname(payload.message)
        when "USER"
          set_user(payload.message)
        when "PONG"
          pong
        when "PING"
          ping
        when "PRIVMSG"
          private_message(payload.receiver.to_s, payload.message)
        end
      end
      if socket.closed?
        Server.remove_connection(nickname.to_s) unless nickname.to_s.empty?
      end
      
    end

    def set_nickname(new_nickname)
      if Server.nickname_used?(new_nickname)
        send_message(":localhost", Numerics::ERR_NICKNAMEINUSE, new_nickname, ":Nickname is already in used")
        return
      end
      changed = !nickname.to_s.empty?
      old_nickname = nickname

      if changed
        begin
          Log.debug { "changing nickname to: #{new_nickname} " }
          Server.changed_nickname(old_nickname.to_s, new_nickname)
          send_message(":#{old_nickname}", "NICK", new_nickname)
          @nickname = new_nickname
        rescue e : Exception
          Log.debug { "error, nickname is not used: #{nickname} " }
          @nickname = old_nickname
          send_message(":localhost", Numerics::ERR_ERRONEUSNICKNAME, old_nickname, ":Nickname is not used.")
        end
      else
        Log.debug { "Set nickname to: #{new_nickname} " }
        @nickname = new_nickname
        send_message(":localhost", "NICK", new_nickname)
      end
    end

    def set_user(user_message)
      users_messages = user_message.split(" ", 4)
      @mode = users_messages[1]
      @user = users_messages.first
      @realname = users_messages[3].sub(":", "")
      Log.debug { "Set user to: #{user} with real name #{realname}" }
      Circed::Server.welcome_message(self)
      pinger
    end

    def private_message(receiver : String, message : String)
      client = Server.get_client(receiver)

      return unless client

      client.not_nil!.send_message(":#{nickname}!#{user}@#{socket.remote_address}", "PRIVMSG", receiver, "#{message}")
    end

    def join_channel
    end

    def part_channel
    end

    def quit
      close
    end

    def send_message(message)
      Log.info { message }
      socket.puts(message + "\n")
    end

    def notice(message)
      send_message(":#{message}")
    end

    def send_message(prefix, command, *params)
      message = "#{prefix} #{command} #{params.join(" ")}\n"
      Log.info { message }
      socket.puts(message)
    end

    def close
      socket.close
      raise ClosedClient.new("closed")
    end

    def pong
      @last_answered = Time.utc
      Log.debug { "PONG #{@nickname}" }
    end

    def ping
      @last_answered = Time.utc
      Log.debug { "PING #{@nickname}" }
      send_message("PONG #{@nickname}")
    end
  end
end
