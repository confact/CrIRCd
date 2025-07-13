module Circed
  class Actions::Topic
    extend Circed::ActionHelper

    def self.call(sender : Client, message : Array(String))
      channel_name = message.first

      return unless sender.nickname

      topic = message[1..-1].join(" ")
      irc_service = Infrastructure::ServiceLocator.irc_service

      # Use IRC service to set topic with full validation
      irc_service.set_topic(sender, channel_name, topic)
    end
  end
end
