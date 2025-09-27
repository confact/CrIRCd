# Base service doesn't need SSL socket directly
# require "../network/ssl_socket"

module Circed::Services
  # Base class for IRC services (ChanServ, UserServ, etc.)
  abstract class BaseService
    getter nickname : String
    getter username : String
    getter hostname : String
    getter realname : String

    def initialize(@nickname : String, @username : String, @hostname : String, @realname : String)
    end

    # Send a message to a user
    def send_message(target_nick : String, message : String)
      if user = get_user(target_nick)
        user.send_message(":#{nickname}!#{username}@#{hostname} PRIVMSG #{target_nick} :#{message}")
      end
    end

    # Send a notice to a user
    def send_notice(target_nick : String, message : String)
      if user = get_user(target_nick)
        user.send_message(":#{nickname}!#{username}@#{hostname} NOTICE #{target_nick} :#{message}")
      end
    end

    # Get user by nickname
    private def get_user(nickname : String)
      Circed::Infrastructure::ServiceLocator.user_repository.get_client(nickname)
    end

    # Abstract method to handle incoming messages
    abstract def handle_message(sender : String, command : String, params : Array(String))

    # Register service with the network
    def register_with_network
      # Add the service as a virtual user to network state
      Network::NetworkState.add_user(
        nickname: @nickname,
        username: @username,
        hostname: @hostname,
        realname: @realname,
        server: Server.config.host,
        hopcount: 0
      )
    end
  end
end
