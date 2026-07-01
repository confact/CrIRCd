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
          mode_params = message.size > 2 ? message[2..] : [] of String

          # Use IRC service for mode changes with full validation
          irc_service.change_mode(sender, target, mode_string, mode_params)
        else
          irc_service.query_mode(sender, target)
        end
      else
        # User mode
        if message.size > 1 && (message[1].starts_with?("+") || message[1].starts_with?("-"))
          mode_string = message[1]

          # Use IRC service for user mode changes
          irc_service.change_mode(sender, target, mode_string)
        else
          irc_service.query_mode(sender, target)
        end
      end
    end
  end
end
