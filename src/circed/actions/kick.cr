require "./base_action"

module Circed
  class Actions::Kick < Actions::ChannelAction
    protected def self.execute_action(sender : Client, message : Array(String)) : Nil
      Log.debug { "kick: #{message}" }

      channel_name = message.first
      return unless Utils::IrcUtils.validate_channel_name(sender, channel_name)

      kicked_nickname = message[1]
      reason = message[2..-1].join(" ") if message.size > 2
      irc_service = Infrastructure::ServiceLocator.irc_service

      # Use IRC service to kick user with full validation
      unless irc_service.kick_user(sender, channel_name, kicked_nickname, reason)
        # IRCService handles all validation internally and sends appropriate errors
      end
    end
  end
end
