module Circed
  class Pingpong
    @last_ping : Time?
    @last_pong : Time?
    @stop = Channel(Nil).new

    getter client : Client | LinkServer

    def initialize(@client : Client | LinkServer)
      every(20.seconds) do
        Log.info { "pinged #{nickname}" }
        @last_ping = Time.utc
        client.send_message(create_ping_message)
      end

      every(30.seconds) do
        last_pong_time = @last_pong
        if last_pong_time && last_pong_time < 1.minutes.ago
          Log.debug { "PONG timedout for #{nickname} - closing socket" }
          stop
          client.close
        end
      end
    end

    def ping(params : Array(String))
      client.send_message(create_pong_message(params))
      @last_ping = Time.utc
    end

    def pong(params : Array(String))
      last_ping = @last_ping
      if last_ping.nil? || last_ping < 5.seconds.ago
        Log.debug { "PONG #{nickname}" }
        client.send_message(create_ping_message)
      end
      @last_pong = Time.utc
      @last_ping = @last_pong
    end

    def stop : Nil
      @stop.close
    end

    def nickname
      @client.nickname
    end

    private def every(interval : Time::Span, &block) : Nil
      spawn do
        loop do
          select
          when timeout(interval)
            break if client.closed?
            block.call
          when @stop.receive?
            break
          end
        end
      end
    end

    private def create_ping_message : FastIRC::Message
      prefix = FastIRC::Prefix.new(source: Server.name, user: nil, host: nil)
      FastIRC::Message.new("PING", [nickname.to_s, Server.name], prefix: prefix)
    end

    private def create_pong_message(params) : FastIRC::Message
      prefix = FastIRC::Prefix.new(source: Server.name, user: nil, host: nil)
      FastIRC::Message.new("PONG", params, prefix: prefix)
    end
  end
end
