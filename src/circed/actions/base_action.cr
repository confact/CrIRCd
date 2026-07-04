require "../mixins/unified_messaging"
require "../performance/metrics"
require "../utils/irc_utils"

module Circed
  module Actions
    # Base class for IRC actions to eliminate code duplication
    # Provides common functionality used across all action classes
    abstract class BaseAction
      extend ActionHelper

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

      # Common user validation
      protected def self.validate_user_exists(sender : Client, nickname : String) : Domain::User?
        user = user_repository.get(nickname)
        unless user
          Utils::IrcUtils.send_no_such_nick_error(sender, nickname)
          return nil
        end
        user
      end

      # Common channel validation
      protected def self.validate_channel_exists(sender : Client, channel_name : String) : Domain::Channel?
        channel = channel_repository.get_channel(channel_name)
        unless channel
          Utils::IrcUtils.send_no_such_channel_error(sender, channel_name)
          return nil
        end
        channel
      end

      # Check if user is in channel
      protected def self.validate_user_in_channel(sender : Client, channel : Domain::Channel, user_nickname : String) : Bool
        unless channel.members.has_key?(user_nickname)
          Utils::IrcUtils.send_not_on_channel_error(sender, channel.name)
          return false
        end
        true
      end

      # Check if user has channel privileges
      protected def self.validate_channel_privileges(sender : Client, channel : Domain::Channel, required_mode : Char) : Bool
        nickname = sender.nickname
        return false unless nickname
        unless Utils::IrcUtils.user_has_channel_mode?(channel, nickname, required_mode)
          Utils::IrcUtils.send_not_operator_error(sender, channel.name)
          return false
        end
        true
      end

      # Send success response for actions that complete successfully
      protected def self.send_success_response(sender : Client, code : String, message : String)
        sender.send_message(Server.clean_name, code, sender.nickname, ":#{message}")
      end

      # Log action execution for debugging
      protected def self.log_action(sender : Client, action_name : String, details : String = "")
        Log.debug { "#{action_name} executed by #{sender.nickname}: #{details}" }
      end

      # Send message to user's socket
      protected def self.send_to_user(user : Client, &block : (Client, IO?) -> Void)
        block.call(user, user.socket)
      end

      # Send message to all users in user's channels (optimized)
      protected def self.send_to_user_channel(user : Client, &block : (Client, IO?) -> Void)
        return unless user.nickname

        channel_repo = channel_repository
        user_repo = user_repository

        # Find all channels the user is in
        user_channels = channel_repo.find_user_channels(user.nickname)

        # Collect all unique users from these channels
        unique_users = Set(String).new

        user_channels.each do |channel|
          channel.members.each_key { |nickname| unique_users << nickname }
        end

        # Send to each user
        unique_users.each do |nickname|
          if client = user_repo.get_client(nickname)
            block.call(client, client.socket)
          end
        end
      end

      # Parse and send IRC message (optimized)
      protected def self.parse(sender : Client, args : Array(String), io : IO)
        return unless sender.nickname

        if args.size == 1
          io << ':' << sender.hostmask << " NICK :" << args[0] << '\n'
        else
          io << ':' << sender.hostmask
          args.each do |arg|
            io << ' ' << arg
          end
          io << '\n'
        end
      end
    end

    # Specialized base class for channel-related actions
    abstract class ChannelAction < BaseAction
      # Template method for channel actions
      def self.call(sender : Client, channel_name : String, *args)
        super(sender, channel_name, *args)
      end

      protected def self.validate_action_specific(sender : Client) : Bool
        true # Channel actions typically don't need extra validation beyond base
      end

      # Helper to validate channel name format
      protected def self.validate_channel_name(sender : Client, channel_name : String) : Bool
        Utils::IrcUtils.validate_channel_name(sender, channel_name)
      end

      # Get or create channel (for JOIN-like actions)
      protected def self.get_or_create_channel(channel_name : String) : Domain::Channel
        channel_repo = channel_repository
        channel = channel_repo.get_channel(channel_name)

        unless channel
          channel = Domain::Channel.new(channel_name)
          channel_repo.add_channel(channel)
        end

        channel
      end
    end

    # Specialized base class for user-related actions
    abstract class UserAction < BaseAction
      # Template method for user actions
      def self.call(sender : Client, target_nickname : String, *args)
        super(sender, target_nickname, *args)
      end

      # Validate target user exists
      protected def self.validate_action_specific(sender : Client) : Bool
        true # User actions handle target validation in execute_action
      end

      # Helper to check if target user is online
      protected def self.user_online?(nickname : String) : Bool
        user_repository.get_client(nickname) != nil
      end
    end
  end
end
