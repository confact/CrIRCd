require "./base_action"

module Circed
  class Actions::Mode < Actions::BaseAction
    protected def self.execute_action(sender : Client, message : Array(String)) : Nil
      return if message.empty?

      target = message.first
      irc_service = Infrastructure::ServiceLocator.irc_service

      if target.starts_with?("#") || target.starts_with?("&")
        # Channel mode
        if message.size > 1 && (message[1].starts_with?("+") || message[1].starts_with?("-"))
          mode_string = message[1]
          mode_target = message[2]?

          # Use IRC service for mode changes with full validation
          irc_service.change_mode(sender, target, mode_string, mode_target)
        else
          # Query mode (not implemented yet)
          Log.info { "Mode query not implemented" }
        end
      else
        # User mode
        if message.size > 1 && (message[1].starts_with?("+") || message[1].starts_with?("-"))
          mode_string = message[1]

          # Use IRC service for user mode changes
          irc_service.change_mode(sender, target, mode_string)
        else
          # Query user mode (not implemented yet)
          Log.info { "User mode query not implemented" }
        end
      end
    end
  end
end
