module Circed
  module SocketHelper
    def safe_send(message : String) : Bool
      return false if closed?
      
      begin
        result = socket.try(&.puts(message))
        !result.nil?
      rescue ex
        Log.error { "Failed to send message: #{ex.message}" }
        false
      end
    end

    def send_error(error_message : String)
      safe_send("ERROR :#{error_message}")
      close
    end

    def send_irc_message(command : String, params : Array(String) = [] of String, prefix : String? = nil)
      message = String.build do |io|
        io << ":#{prefix} " if prefix
        io << command
        params.each { |param| io << " #{param}" }
      end
      safe_send(message)
    end

    def closed? : Bool
      return true if socket.nil?
      socket.try(&.closed?) || false
    end

    private def socket
      @socket
    end

    private def close
      # This should be implemented by the including class
      raise NotImplementedError.new("close method must be implemented")
    end
  end
end