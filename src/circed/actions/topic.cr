require "./base_action"

module Circed
  class Actions::Topic < Actions::ChannelAction
    protected def self.execute_action(sender : Client, message : Array(String)) : Nil
      channel_name = message.first
      irc_service = Infrastructure::ServiceLocator.irc_service

      if message.size == 1
        irc_service.query_topic(sender, channel_name)
      else
        irc_service.update_topic(sender, channel_name, message[1..-1].join(" "))
      end
    end
  end
end
