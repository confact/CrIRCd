module Circed
  module Services
    class RateLimiter
      BURST_TOKENS      = 20.0
      TOKENS_PER_SECOND =  2.0
      EXEMPT_COMMANDS   = {"PONG", "QUIT"}

      @tokens = BURST_TOKENS

      def initialize(@updated_at : Time::Span = Time.monotonic)
      end

      def allow?(command : String, now : Time::Span = Time.monotonic) : Bool
        return true if EXEMPT_COMMANDS.includes?(command)

        @tokens = Math.min(BURST_TOKENS, @tokens + (now - @updated_at).total_seconds * TOKENS_PER_SECOND)
        @updated_at = now

        cost = command_cost(command)
        return false if @tokens < cost

        @tokens -= cost
        true
      end

      private def command_cost(command : String) : Float64
        case command
        when "LIST"
          10.0
        when "NAMES", "WHO"
          5.0
        when "JOIN", "NICK", "WHOIS"
          2.0
        else
          1.0
        end
      end
    end
  end
end
