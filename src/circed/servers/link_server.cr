module Circed
  class LinkServer
    include SocketHelper

    getter name : String
    getter target_host : String
    getter target_port : Int32

    getter socket : IPSocket? = nil

    @pingpong : Pingpong?

    @buffer : Array(String) = [] of String

    def initialize(name, target_host, target_port, password)
      @name = name
      @target_host = target_host
      @target_port = target_port

      @socket = TCPSocket.new(@target_host, @target_port)
      handshake(password)

      listen
    end

    def initialize(socket, buffer)
      @socket = socket
      @buffer = buffer
      remote_addr = socket.remote_address
      @target_host = remote_addr.address
      @target_port = remote_addr.port
      @name = ""  # Will be set during authentication

      authenticate_incoming_server
      listen
    end

    def handshake(password)
      # IRC server handshake protocol
      # Send PASS command for authentication
      safe_send("PASS #{password}")
      
      # Send SERVER command with our server info
      # Format: SERVER <servername> <hopcount> :<info>
      safe_send("SERVER #{Server.name} 1 :Circed IRC Server")
      
      Log.info { "Sent handshake to #{@target_host}:#{@target_port}" }
    end

    def authenticate_incoming_server
      auth_state = AuthenticationState.new
      
      @buffer.each do |line|
        process_authentication_line(line, auth_state)
        return if auth_state.failed?
      end
      
      complete_authentication(auth_state)
    end

    private def process_authentication_line(line, auth_state)
      begin
        payload = FastIRC.parse_line(line)
        case payload.command
        when "PASS"
          process_pass_command(payload, auth_state)
        when "SERVER"
          process_server_command(payload, auth_state)
        end
      rescue ex
        Log.warn { "Failed to parse IRC line during authentication: #{line} - #{ex.message}" }
      end
    end

    private def process_pass_command(payload, auth_state)
      password = payload.params[0]?
      if password == Server.config.link_password
        auth_state.authenticated = true
        Log.info { "Server authentication successful from #{@target_host}" }
      else
        Log.error { "Server authentication failed from #{@target_host}" }
        send_error("Bad Password")
        auth_state.failed = true
      end
    end

    private def process_server_command(payload, auth_state)
      unless auth_state.authenticated
        Log.error { "Server tried to introduce without authentication: #{@target_host}" }
        send_error("Not authenticated")
        auth_state.failed = true
        return
      end

      @name = payload.params[0]? || "unknown"
      auth_state.server_introduced = true
      Log.info { "Server #{@name} introduced from #{@target_host}" }
      
      # Send our server info back
      safe_send("SERVER #{Server.name} 1 :Circed IRC Server")
    end

    private def complete_authentication(auth_state)
      unless auth_state.complete?
        Log.error { "Incomplete handshake from #{@target_host}" }
        send_error("Incomplete handshake")
        return
      end
      
      setup([@name])
    end

    private class AuthenticationState
      property authenticated : Bool = false
      property server_introduced : Bool = false
      property failed : Bool = false

      def complete?
        authenticated && server_introduced
      end

      def failed?
        failed
      end
    end

    def listen
      while !socket.not_nil!.closed?
        FastIRC.parse(socket.not_nil!) do |payload|
          case payload.command
          when "ERROR"
            handle_error(payload)
          when "PING"
            ping(payload.params)
          when "PONG"
            pong(payload.params)
          when "SERVER"
            # Additional servers in the network
            Log.info { "Remote server introducing: #{payload.params[0]}" }
          when "PRIVMSG"
            handle_privmsg(payload)
          when "JOIN", "PART", "QUIT", "NICK", "MODE"
            # Forward other IRC commands to all servers
            message = String.build do |io|
              payload.to_s(io)
            end
            ServerHandler.servers.each do |server|
              next if server == self
              server.send_message(message)
            end
          else
            Log.debug { "Unhandled server command: #{payload.command}" }
          end
        end

        if closed?
          Log.info { "Server connection closed: #{@name}" }
          break
        end
      end
    end

    def setup(params)
      @pingpong = Pingpong.new(self)
      @name = params[0]
      ServerHandler.add_server(self)
    end

    def pong(params : Array(String))
      @pingpong.try(&.pong(params))
      Log.debug { "PONG #{@name}" }
      # send_message("PING :#{@name} :localhost")
    end

    def ping(params : Array(String))
      @pingpong.try(&.ping(params))
      # return if @last_checked && @last_checked.not_nil! < 5.seconds.ago
    end

    def closed? : Bool
      socket.try(&.closed?) || false
    end

    def send_message(message)
      Log.info { message }
      safe_send(message)
    end

    def send_message(prefix, command, *params)
      send_irc_message(command, params.to_a, prefix)
    end

    def close
      Log.info { "Closing server connection to #{@name}" }
      cleanup_pingpong
      ServerHandler.remove_server(self)
      socket.try(&.close)
    end

    private def cleanup_pingpong
      @pingpong.try(&.stop_ping)
      @pingpong.try(&.stop_pong_check)
    end

    def handle_message(message)
      return if closed?
      send_message(message)
    end

    def handle_error(payload)
      Log.error { "Server #{@name} sent ERROR: #{payload.params.join(" ")}" }
      close
    end

    def handle_privmsg(payload)
      # Forward PRIVMSG to all other connected servers except the sender
      message = String.build do |io|
        payload.to_s(io)
      end
      
      ServerHandler.servers.each do |server|
        next if server == self
        server.send_message(message)
      end
      
      # Also forward to local clients if the target is a local user/channel
      # This would integrate with existing client message handling
    end

    def nickname
      @name
    end

    def host
      @target_host
    end
  end
end