require "../performance/metrics"

module Circed
  # Unified messaging module that consolidates functionality from SocketHelper and ActionHelper
  # Eliminates code duplication across Client, LinkServer, and Actions
  module UnifiedMessaging
    # Socket-based messaging with performance tracking
    def safe_send(message : String) : Bool
      return false if closed?

      Performance::Metrics.time_message_processing do
        begin
          return false unless socket_ref = socket

          socket_ref.write(message.to_slice)
          socket_ref.write("\r\n".to_slice)
          socket_ref.flush
          Performance::Metrics.increment_messages
          true
        rescue ex
          Log.error { "Failed to send message: #{ex.message}" }
          false
        end
      end
    end

    # Legacy send_message method for compatibility
    def send_message(message : String)
      safe_send(message)
    end

    # Send error and close connection
    def send_error(error_message : String)
      safe_send("ERROR :#{error_message}")
      close
    end

    # Build and send IRC message with prefix and parameters
    def send_irc_message(command : String, params : Array(String) = [] of String, prefix : String? = nil)
      message = build_irc_message(command, params, prefix)
      safe_send(message)
    end

    # Send error message to client with error code
    def send_client_error(client : Client, code : String, message : String)
      client.send_message(Server.clean_name, code, client.nickname || "*", ":#{message}")
    end

    # Send error message to client with additional parameter
    def send_client_error(client : Client, code : String, item : String, message : String)
      client.send_message(Server.clean_name, code, client.nickname || "*", item, ":#{message}")
    end

    # Send message to all users in user's channels (consolidated from ActionHelper)
    def send_to_user_channels(user : Client, message : String) : Int32
      return 0 unless user.nickname

      channel_repository = Infrastructure::ServiceLocator.channel_repository
      user_repository = Infrastructure::ServiceLocator.user_repository

      # Find all channels the user is in
      user_channels = channel_repository.find_user_channels(user.nickname)

      # Collect unique users from these channels
      unique_users = Set(String).new
      user_channels.each do |channel|
        channel.members.each_key { |nickname| unique_users << nickname }
      end

      # Send to each unique user
      success_count = 0
      unique_users.each do |nickname|
        if client = user_repository.get_client(nickname)
          success_count += 1 if client.safe_send(message)
        end
      end

      Performance::Metrics.increment_messages(success_count.to_u64)
      success_count
    end

    # Send message to specific users efficiently
    def send_to_users(user_nicknames : Array(String), message : String) : Int32
      user_repository = Infrastructure::ServiceLocator.user_repository
      success_count = 0

      user_nicknames.each do |nickname|
        if client = user_repository.get_client(nickname)
          success_count += 1 if client.safe_send(message)
        end
      end

      Performance::Metrics.increment_messages(success_count.to_u64)
      success_count
    end

    # Broadcast message to multiple servers (for server-to-server communication)
    def broadcast_to_servers(message : String, exclude_server : LinkServer? = nil) : Int32
      success_count = 0

      ServerHandler.servers.each do |server|
        next if server == exclude_server
        success_count += 1 if server.safe_send(message)
      end

      Performance::Metrics.increment_messages(success_count.to_u64)
      success_count
    end

    # Format user hostmask efficiently
    def format_hostmask(nickname : String, username : String, hostname : String) : String
      capacity = nickname.size + username.size + hostname.size + 2
      String.build(capacity: capacity) do |io|
        io << nickname << '!' << username << '@' << hostname
      end
    end

    # Build IRC message with optimal performance
    private def build_irc_message(command : String, params : Array(String), prefix : String?) : String
      # Calculate capacity for optimal String.build performance
      capacity = command.size + params.sum(&.size) + params.size + 10
      capacity += prefix.size + 2 if prefix

      String.build(capacity: capacity) do |io|
        io << ':' << prefix << ' ' if prefix
        io << command

        params.each_with_index do |param, index|
          io << ' '
          # Last parameter with spaces or starting with ':' should be prefixed
          if index == params.size - 1 && (param.includes?(' ') || param.starts_with?(':'))
            io << ':' << param
          else
            io << param
          end
        end
      end
    end

    # Template methods that should be implemented by including classes
    protected def socket
      @socket
    end

    protected def close
      raise NotImplementedError.new("close method must be implemented")
    end

    protected def closed? : Bool
      socket.try(&.closed?) || false
    end
  end

  # Simplified ActionHelper that uses UnifiedMessaging
  module ActionHelper
    include UnifiedMessaging

    # Send error to client (simplified)
    def send_error(client : Client, code : String, message : String)
      send_client_error(client, code, message)
    end

    def send_error(client : Client, code : String, item : String, message : String)
      send_client_error(client, code, item, message)
    end

    # Send to user channels (simplified)
    def send_to_user_channel(user : Client, &block : (Client, IO?) -> Void)
      return unless user.nickname

      channel_repository = Infrastructure::ServiceLocator.channel_repository
      user_repository = Infrastructure::ServiceLocator.user_repository

      user_channels = channel_repository.find_user_channels(user.nickname)
      unique_users = Set(String).new

      user_channels.each do |channel|
        channel.members.each_key { |nickname| unique_users << nickname }
      end

      unique_users.each do |nickname|
        if client = user_repository.get_client(nickname)
          block.call(client, client.socket)
        end
      end
    end

    # Optimized parse method
    def parse(sender : Client, args : Array(String), io : IO)
      return unless sender.nickname

      if args.size == 1
        io << ':' << sender.hostmask << " NICK :" << args[0] << "\r\n"
      else
        io << ':' << sender.hostmask << ' ' << args.join(' ') << "\r\n"
      end
    end
  end
end
