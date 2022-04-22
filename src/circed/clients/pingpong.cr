module Circed
  class Pingpong

    class ClosedClient < Exception; end
    class PingStoppedException < Exception; end

    @last_ping : Time?
    @last_pong : Time?

    @client : Client

    @task_ping : Tasker::Repeat(Int32) | Tasker::Repeat(Nil)
    @task_pong_check : Tasker::Repeat(Int32) | Tasker::Repeat(Nil)

    def initialize(@client : Client)
      @task_ping = Tasker.every(20.seconds) do
        stop_ping if socket.closed?
        Log.info { "pinged #{nickname}" }
        raise PingStoppedException.new("Stoped") if socket.closed?
        @last_ping = Time.utc
        send_message(create_ping_message)
      end
      @task_pong_check = Tasker.every(30.seconds) do
        stop_pong_check if socket.closed?
        if @last_pong && @last_pong.not_nil! < 1.minutes.ago
          Log.debug { "PONG timedout for #{nickname} - closing socket" }
          socket.close
          stop_ping
          stop_pong_check
          UserHandler.remove_connection(nickname.to_s) unless nickname.to_s.empty?
          raise ClosedClient.new("closed")
        end
      end
    end

    def ping(params : Array(String))
      if !@last_pong || (@last_pong && @last_pong.not_nil! < 5.seconds.ago)
        Log.debug { "PONG #{nickname}" }
        send_message(create_pong_message(params))
      end
      @last_ping = Time.utc
    end

    def pong(params : Array(String))
      if !@last_ping || (@last_ping && @last_ping.not_nil! < 5.seconds.ago)
        Log.debug { "PING #{nickname}" }
        send_message(create_ping_message)
      end
      @last_pong = Time.utc
      @last_ping = @last_pong
    end

    def stop_ping
      @task_ping.not_nil!.cancel
    end

    def stop_pong_check
      @task_pong_check.not_nil!.cancel
    end

    def nickname
      @client.nickname
    end

    def send_message(message)
      @client.send_message(message)
    end

    def socket
      @client.socket
    end

    def host
      socket.remote_address
    end

    private def create_ping_message
      #prefix = FastIRC::Prefix.new(source: Server.name)
      String.build do |io|
        prefix = FastIRC::Prefix.new(source: Server.name, user: nickname, host: host.to_s)
        FastIRC::Message.new("PING", [":#{nickname}", Server.clean_name], prefix: prefix).to_s(io)
      end
    end

    private def create_pong_message(params)
      prefix = FastIRC::Prefix.new(source: Server.name, user: nickname, host: host.to_s)
      String.build do |io|
        FastIRC::Message.new("PONG", params, prefix: prefix).to_s(io)
      end
    end
  end
end
