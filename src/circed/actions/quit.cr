require "./base_action"

module Circed
  class Actions::Quit < Actions::BaseAction
    protected def self.execute_action(sender : Client, reason : String? = nil) : Nil
      irc_service = Infrastructure::ServiceLocator.irc_service
      irc_service.quit_user(sender, reason)
    end
  end
end 