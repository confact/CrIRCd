require "./base_action"

module Circed
  class Actions::Join < Actions::BaseAction
    protected def self.execute_action(sender : Client, channel_name : String, password : String? = nil) : Nil
      irc_service = Infrastructure::ServiceLocator.irc_service
      irc_service.join_channel(sender, channel_name, password)
    end
  end
end
