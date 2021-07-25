module Circed
  module Pinger
    class ClosedClient < Exception; end
    class PingStoppedException < Exception; end
    
    private def pinger
      @task_ping = Tasker.every(20.seconds) do
        @task_ping.not_nil!.cancel if socket.closed?
        Log.info { "pinged #{@nickname}" }
        raise PingStoppedException.new("Stoped") if socket.closed?
        @last_checked = Time.utc
        send_message("PING :#{@nickname} :localhost")
      end
      @task_pong_check = Tasker.every(30.seconds) do
        @task_pong_check.not_nil!.cancel if socket.closed?
        if @last_answered && @last_answered.not_nil! < 1.minutes.ago
          Log.debug { "PONG timedout for #{@nickname} - closing socket" }
          @socket.close
          @task_ping.not_nil!.cancel
          @task_pong_check.not_nil!.cancel
          Server.remove_connection(@nickname.to_s) unless @nickname.to_s.empty?
          raise ClosedClient.new("closed")
        end
      end
    end
  end
end
