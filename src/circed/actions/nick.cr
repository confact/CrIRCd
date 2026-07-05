require "./base_action"

module Circed
  class Actions::Nick < Actions::BaseAction
    # Override validation since NICK can be used before registration is complete
    protected def self.validate_sender(sender : Client) : Bool
      true # NICK is allowed even if nickname is not yet set
    end

    protected def self.execute_action(sender : Client, new_nickname : String) : Nil
      # Validate nickname format first
      unless Utils::IrcUtils.valid_nickname?(new_nickname)
        sender.send_message(Server.clean_name, Numerics::ERR_ERRONEUSNICKNAME, new_nickname, ":Erroneous nickname")
        return
      end

      old_nickname = sender.nickname

      # Check if nickname is already in use (local or remote)
      user_repo = user_repository
      if user_repo.has_client?(new_nickname) || Network::NetworkState.get_user(new_nickname)
        Utils::IrcUtils.send_nickname_in_use_error(sender, new_nickname)
        return
      end

      if old_nickname.nil?
        # Initial nickname setting during registration
        sender.nickname = new_nickname

        # Add client to user repository
        user_repo.add_client(sender)

        # Create domain user if we have enough information
        if user_info = sender.user
          domain_user = Domain::User.new(
            new_nickname,
            user_info.name,
            sender.hostname,
            user_info.realname,
            Server.name
          )
          user_repo.add(new_nickname, domain_user)
          sender.set_hostmask
        end

        sender.complete_registration
      else
        # Use IRC service for nickname change (it will update the client's nickname)
        irc_service = Infrastructure::ServiceLocator.irc_service
        irc_service.change_nickname(sender, new_nickname)
      end
    end
  end
end
