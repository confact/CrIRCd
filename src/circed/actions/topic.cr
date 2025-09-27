require "./base_action"

module Circed
  class Actions::Topic < Actions::ChannelAction
    protected def self.execute_action(sender : Client, message : Array(String)) : Nil
      channel_name = message.first
      topic = message[1..-1].join(" ")

      irc_service = Infrastructure::ServiceLocator.irc_service
      irc_service.update_topic(sender, channel_name, topic)
    end
  end
end
