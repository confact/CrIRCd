module Circed
  class Actions::Join
    extend Circed::ActionHelper

    def self.call(sender, channel : String, password : String? = nil)
      channels = channel.split(",")
      irc_service = Infrastructure::ServiceLocator.irc_service

      channels.each do |ch|
        ch = ch.strip

        if ch.empty?
          send_error(sender, Numerics::ERR_NOSUCHCHANNEL, ch, "No such channel")
          next
        end

        # Use IRC service for validation and joining
        unless irc_service.join_channel(sender, ch, password)
          # IRCService handles all validation internally and sends appropriate errors
        end
      end
    end
  end
end
