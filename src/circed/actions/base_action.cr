require "../performance/metrics"
require "../utils/irc_utils"

module Circed
  module Actions
    # Base class for IRC actions to eliminate code duplication
    # Provides common functionality used across all action classes
    abstract class BaseAction
      # Template method pattern for action execution
      def self.call(sender : Client, *args)
        Performance::Metrics.time_message_processing do
          validate_sender(sender) && execute_action(sender, *args)
        end
      end

      # Validation methods that can be overridden
      protected def self.validate_sender(sender : Client) : Bool
        unless sender.nickname
          Utils::IrcUtils.send_not_registered_error(sender)
          return false
        end

        # Can be overridden for additional validation
        validate_action_specific(sender)
      end

      # Template method for action-specific validation
      protected def self.validate_action_specific(sender : Client) : Bool
        true # Override in subclasses if needed
      end

      # Method that must be implemented by subclasses
      protected def self.execute_action(sender : Client, *args) : Nil
        raise NotImplementedError.new("#{self} must implement execute_action")
      end

      # Common helper methods
      protected def self.user_repository
        Infrastructure::ServiceLocator.user_repository
      end

      protected def self.channel_repository
        Infrastructure::ServiceLocator.channel_repository
      end

      protected def self.notification_service
        Infrastructure::ServiceLocator.notification_service
      end
    end
  end
end
