require "./base_action"

module Circed
  class Actions::Part < Actions::BaseAction
    protected def self.execute_action(sender : Client, channel_name : String, reason : String? = nil) : Nil
      irc_service = Infrastructure::ServiceLocator.irc_service
      irc_service.part_channel(sender, channel_name, reason)
    end
  end
end
