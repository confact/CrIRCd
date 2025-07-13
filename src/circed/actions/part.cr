module Circed
  class Actions::Part
    extend Circed::ActionHelper

    def self.call(sender, channel : String, reason : String? = nil)
      channels = channel.split(",")
      irc_service = Infrastructure::ServiceLocator.irc_service

      channels.each do |ch|
        ch = ch.strip

        next if ch.empty?

        # Use IRC service for parting with full validation
        irc_service.part_channel(sender, ch, reason)
      end
    end
  end
end
