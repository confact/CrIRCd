require "./base_action"

module Circed
  class Actions::Invite < Actions::BaseAction
    protected def self.execute_action(sender : Client, invited_user : String, channel_name : String) : Nil
      return unless sender_nick = sender.nickname

      channel_repo = channel_repository

      if channel = channel_repo[channel_name]?
        # Check if sender is in the channel
        unless channel.has_member?(sender_nick)
          Utils::IrcUtils.send_not_on_channel_error(sender, channel_name)
          return
        end

        if channel.invite_only? && !Utils::IrcUtils.user_is_operator?(channel, sender_nick)
          Utils::IrcUtils.send_not_operator_error(sender, channel_name)
          return
        end
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
      if away_message = user_repo[invited_user]?.try(&.away_message)
        sender.send_message(Server.clean_name, Numerics::RPL_AWAY, sender_nick, invited_user, ":#{away_message}")
      end

      channel_repo[channel_name]?.try(&.add_invite(invited_user))
    end
  end
end
