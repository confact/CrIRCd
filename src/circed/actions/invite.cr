require "./base_action"

module Circed
  class Actions::Invite < Actions::BaseAction
    protected def self.execute_action(sender : Client, invited_user : String, channel_name : String) : Nil
      return unless sender_nick = sender.nickname

      # Validate channel name format
      unless Utils::IrcUtils.valid_channel_name?(channel_name)
        Utils::IrcUtils.send_channel_error(sender, channel_name)
        return
      end

      # Check if channel exists
      channel_repo = channel_repository
      unless channel_repo.exists?(channel_name)
        Utils::IrcUtils.send_no_such_channel_error(sender, channel_name)
        return
      end

      # Check if sender is in the channel
      unless channel_repo.user_in_channel?(channel_name, sender_nick)
        Utils::IrcUtils.send_not_on_channel_error(sender, channel_name)
        return
      end

      # Check if invited user exists
      user_repo = user_repository
      unless user_repo.has_client?(invited_user)
        Utils::IrcUtils.send_no_such_nick_error(sender, invited_user)
        return
      end

      # Check if user is already in channel
      if channel_repo.user_in_channel?(channel_name, invited_user)
        # Send user already on channel error (443)
        sender.send_message(Server.clean_name, "443", sender_nick, invited_user, channel_name, ":is already on channel")
        return
      end

      # Send invitation to target user
      if target_client = user_repo.get_client(invited_user)
        target_client.send_message(":#{sender.hostmask}", "INVITE", invited_user, ":#{channel_name}")
      end

      # Send confirmation to sender (RPL_INVITING - 341)
      sender.send_message(Server.clean_name, "341", sender_nick, invited_user, channel_name)

      # Add user to channel's invite list (for +i mode)
      irc_service = Infrastructure::ServiceLocator.irc_service
      irc_service.add_channel_invite(channel_name, invited_user)
    end
  end
end
