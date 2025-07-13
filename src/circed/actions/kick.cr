module Circed
  class Actions::Kick
    extend Circed::ActionHelper

    def self.call(sender, message)
      Log.debug { "kick: #{message}" }

      channel_name = message.first
      return send_error(sender, Numerics::ERR_BADCHANMASK, channel_name, "Wrong channel format") unless channel_name.starts_with?("#")

      return unless sender.nickname

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
