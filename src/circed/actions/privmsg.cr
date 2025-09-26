require "./base_action"

module Circed
  class Actions::Privmsg < Actions::BaseAction
    protected def self.execute_action(sender : Client, target : String, message : String) : Nil
      irc_service = Infrastructure::ServiceLocator.irc_service
      irc_service.route_message(sender, target, message)
    end
  end
end
