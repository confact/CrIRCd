module Circed
  class Pingpong
    class ClosedClient < Exception; end

    class PingStoppedException < Exception; end

    @last_ping : Time?
    @last_pong : Time?

    getter client : Client | LinkServer

    @task_ping : Tasker::Repeat(Int32) | Tasker::Repeat(Nil)
    @task_pong_check : Tasker::Repeat(Int32) | Tasker::Repeat(Nil)

    def initialize(@client : Client | LinkServer)
      @task_ping = Tasker.every(20.seconds) do
        stop_ping if client.closed?
        Log.info { "pinged #{nickname}" }
        raise PingStoppedException.new("Stoped") if client.closed?
        @last_ping = Time.utc
        send_message(create_ping_message)
      end
      @task_pong_check = Tasker.every(30.seconds) do
        stop_pong_check if client.closed?
        last_pong_time = @last_pong
        if last_pong_time && last_pong_time < 1.minutes.ago
          Log.debug { "PONG timedout for #{nickname} - closing socket" }
          stop_ping
          stop_pong_check
          client.close
        end
      end
    end

    def ping(params : Array(String))
      handle_heartbeat("PING", @last_pong) do
        send_message(create_pong_message(params))
      end
      @last_ping = Time.utc
    end

    def pong(params : Array(String))
      handle_heartbeat("PONG", @last_ping) do
        send_message(create_ping_message)
      end
      @last_pong = Time.utc
      @last_ping = @last_pong
    end

    private def handle_heartbeat(type : String, last_time : Time?, &)
      if last_time.nil? || last_time < 5.seconds.ago
        Log.debug { "#{type} #{nickname}" }
        yield
      end
    end

    def stop_ping
      @task_ping.try(&.cancel)
    end

    def stop_pong_check
      @task_pong_check.try(&.cancel)
    end

    def nickname
      @client.nickname
    end

    def send_message(message)
      @client.send_message(message)
    end

    def host
      client.try(&.host) || ""
    end

    private def create_ping_message
      # prefix = FastIRC::Prefix.new(source: Server.name)
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
