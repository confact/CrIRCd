module Circed
  class Actions::Mode
    extend Circed::ActionHelper

    def self.call(sender, message : Array(String))
      return if message.empty?

      user_or_channel = message.first
      if user_or_channel.starts_with?("#")
        if message.size > 1 && (message[1].starts_with?("+") || message[1].starts_with?("-"))
          # channel mode
          target_nick = message[2]?
          mode_string = message[1]

          irc_service = Infrastructure::ServiceLocator.irc_service
          # Use IRC service for mode changes with full validation
          irc_service.change_mode(sender, user_or_channel, mode_string, target_nick)
        else
          # user mode in channel - not implemented
          Log.info { "User mode in channel not implemented" }
        end
      else
        # User mode changes - not implemented
        Log.info { "User mode changes not implemented" }
      end
    end
  end
end
