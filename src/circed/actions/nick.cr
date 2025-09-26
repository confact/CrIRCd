require "./base_action"

module Circed
  class Actions::Nick < Actions::BaseAction

    protected def self.execute_action(sender : Client, new_nickname : String) : Nil

      old_nickname = sender.nickname

      # Check if nickname is already in use (local or remote)
      user_repository = get_user_repository
      if user_repository.has_client?(new_nickname) || Network::NetworkState.get_user(new_nickname)
        Utils::IrcUtils.send_nickname_in_use_error(sender, new_nickname)
        return
      end

      if old_nickname.nil?
        # Initial nickname setting during registration
        sender.nickname = new_nickname
        
        # Add client to user repository
        user_repository.add_client(sender)
        
        # Create domain user if we have enough information
        if user_info = sender.user
          hostname = sender.host || "localhost"
          domain_user = Domain::User.new(
            new_nickname,
            user_info.name,
            hostname,
            user_info.realname,
            Server.config.host
          )
          user_repository.add(new_nickname, domain_user)
        end
        
        # Note: Registration completion is handled elsewhere in the system
      else
        # Use IRC service for nickname change (it will update the client's nickname)
        irc_service = Infrastructure::ServiceLocator.irc_service
        irc_service.change_nickname(sender, new_nickname)
      end
    end
  end
end
