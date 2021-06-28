require "tasker"
module Circed
  class Client
    class ClosedClient < Exception; end
    class PingStoppedException < Exception; end

    getter socket : TCPSocket
    getter nickname : String?
    getter mode : String?
    getter user : String?
    getter realname : String?

    @last_checked : Time?
    @last_answered : Time?

    @task_ping : Tasker::Repeat(Int32)?
    @task_pong_check : Tasker::Repeat(Int32) | Tasker::Repeat(Nil) | Nil

    def initialize(@socket : Socket)

    end

    def setup
      message_handling
    end

    def message_handling
      while message = @socket.gets
        Log.info { "got this message: #{message} "}
        payload = Payload.parse_message(message.to_s)

        Log.info { "message: #{payload.inspect} "}
        return if payload.nil?

        set_nickname(payload.message) if payload.message_type == "NICK"
        set_user(payload.message) if payload.message_type == "USER"
        pong if payload.message_type == "PONG"
      end
    end

    def set_nickname(nickname)
      @nickname = nickname
      Log.info { "Set nickname to: #{nickname} "}
      @socket.send("NICK #{@nickname} localhost")
    end

    def set_user(user_message)
      users_messages = user_message.split(" ", 4)
      @mode = users_messages[1]
      @user = users_messages.first
      @realname = users_messages[3].sub(":", "")
      Log.info { "Set user to: #{@user} with real name #{@realname}"}
      Circed::Server.welcome_message(self)
      pinger
    end

    def join_channel

    end

    def part_channel

    end

    def quit
      close
    end

    def send_message(message)
      @socket.send(message)
    end

    def send_message(prefix, command, *params)
      message = "#{prefix} #{command} #{params.join(" ")}"
      Log.info { message }
      puts @socket.send(message)
    end

    def close
      @socket.close
      raise ClosedClient.new("closed")
    end

    def pong
      @last_answered = Time.utc
      Log.info { "PONG #{@nickname}" }
    end

    private def welcome_message

    end

    private def pinger
      @task_ping = Tasker.every(20.seconds) do
        Log.info { "pinged #{@nickname}" }
        raise PingStoppedException.new("Stoped") if socket.closed?
        @last_checked = Time.utc
        @socket.send("PING #{@nickname}")
      end
      @task_pong_check = Tasker.every(1.minute) do
        if @last_answered && @last_answered.not_nil! < 2.minutes.ago
          Log.info { "PONG timedout for #{@nickname} - closing socket" }
          @socket.close
          @task_ping.not_nil!.cancel
          @task_pong_check.not_nil!.cancel
          raise ClosedClient.new("closed")
        end
      end
    end
  end
end
