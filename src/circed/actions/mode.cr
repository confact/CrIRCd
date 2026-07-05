require "./base_action"

module Circed
  class Actions::Mode < Actions::BaseAction
    protected def self.execute_action(sender : Client, message : Array(String)) : Nil
      return if message.empty?

      target = message.first
      irc_service = Infrastructure::ServiceLocator.irc_service

      if mode_change?(message)
        irc_service.change_mode(sender, target, message[1], mode_params(message))
      else
        irc_service.query_mode(sender, target)
      end
    end

    private def self.mode_change?(message : Array(String)) : Bool
      message.size > 1 && (message[1].starts_with?("+") || message[1].starts_with?("-"))
    end

    private def self.mode_params(message : Array(String)) : Array(String)
      message.size > 2 ? message[2..] : [] of String
    end
  end
end
