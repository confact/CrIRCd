# Consolidated IRC service for common operations
# Simplifies and eliminates duplication across action classes

module Circed
  module Services
    class IRCService
      def initialize(@user_repository : Repositories::UserRepository,
                     @channel_repository : Repositories::ChannelRepository,
                     @notification_service : NotificationService)
      end
      
      private def send_error(client : Client, code, item : String, message : String)
        client.send_message(Server.clean_name, code, client.nickname, item, ":#{message}")
      end
      
      private def send_error(client : Client, code, message : String)
        client.send_message(Server.clean_name, code, client.nickname, ":#{message}")
      end

      # User joins a channel with proper validation and notifications
      def join_channel(client : Client, channel_name : String, password : String? = nil) : Bool
        return false unless nickname = client.nickname
        
        # Basic format validation
        unless channel_name.starts_with?("#") || channel_name.starts_with?("&")
          send_error(client, Numerics::ERR_BADCHANMASK, channel_name, "Wrong channel format")
          return false
        end
        
        # Get or create channel
        channel = @channel_repository.create_channel(channel_name)
        
        # Already in channel?
        if channel.has_member?(nickname)
          send_error(client, Numerics::ERR_USERONCHANNEL, channel_name, "User is already in channel")
          return false
        end
        
        # Validation checks
        unless validate_join_permissions(client, channel, password)
          return false
        end
        
        # Add user to channel
        channel.add_member(nickname)
        
        # Make first user an operator
        if channel.member_count == 1
          channel.members[nickname] << 'o'
        end
        
        # Send notifications
        @notification_service.notify_user_joined(nickname, channel_name)
        
        true
      end

      # User parts from a channel
      def part_channel(client : Client, channel_name : String, reason : String? = nil) : Bool
        return false unless nickname = client.nickname
        
        channel = @channel_repository.get(channel_name)
        unless channel
          send_error(client, Numerics::ERR_NOSUCHCHANNEL, channel_name, "No such channel")
          return false
        end
        
        unless channel.has_member?(nickname)
          send_error(client, Numerics::ERR_NOTONCHANNEL, channel_name, "You're not on that channel")
          return false
        end
        
        # Remove user from channel
        channel.remove_member(nickname)
        
        # Send notifications
        @notification_service.notify_user_parted(nickname, channel_name, reason)
        
        # Clean up empty channel
        if channel.is_empty?
          @channel_repository.remove(channel_name)
        end
        
        true
      end

      # Set channel topic with validation
      def set_topic(client : Client, channel_name : String, topic : String) : Bool
        return false unless nickname = client.nickname
        
        # Basic format validation
        unless channel_name.starts_with?("#") || channel_name.starts_with?("&")
          send_error(client, Numerics::ERR_BADCHANMASK, channel_name, "Wrong channel format")
          return false
        end
        
        channel = @channel_repository.get(channel_name)
        unless channel
          send_error(client, Numerics::ERR_NOSUCHCHANNEL, channel_name, "No such channel")
          return false
        end
        
        # Check if user is in channel
        unless channel.has_member?(nickname)
          send_error(client, Numerics::ERR_NOTONCHANNEL, channel_name, "You're not on that channel")
          return false
        end
        
        # Check if user is operator
        user_modes = channel.members[nickname]?
        unless user_modes && user_modes.includes?('o')
          send_error(client, Numerics::ERR_CHANOPRIVSNEEDED, channel_name, "You're not an operator")
          return false
        end
        
        # Set topic
        channel.topic = topic
        channel.topic_set_by = nickname
        channel.topic_set_at = Time.utc
        
        # Send notifications
        @notification_service.notify_topic_change(channel_name, topic, nickname)
        
        true
      end

      # Change channel or user modes
      def change_mode(client : Client, channel_name : String, mode_string : String, target : String? = nil) : Bool
        return false unless nickname = client.nickname
        
        channel = @channel_repository.get(channel_name)
        unless channel
          send_error(client, Numerics::ERR_NOSUCHCHANNEL, channel_name, "No such channel")
          return false
        end
        
        # Check if user is in channel and is operator
        unless channel.has_member?(nickname)
          send_error(client, Numerics::ERR_NOTONCHANNEL, channel_name, "You're not on that channel")
          return false
        end
        
        user_modes = channel.members[nickname]?
        unless user_modes && user_modes.includes?('o')
          send_error(client, Numerics::ERR_CHANOPRIVSNEEDED, channel_name, "You're not an operator")
          return false
        end
        
        # Parse mode string
        return false if mode_string.size < 2
        
        adding = mode_string.starts_with?("+")
        mode_char = mode_string[1]
        
        case mode_char
        when 'i', 'm', 'n', 't', 's', 'p' # Simple channel modes
          if adding
            channel.modes << mode_char
          else
            channel.modes.delete(mode_char)
          end
          
        when 'o', 'h', 'v' # User modes
          return false unless target && channel.has_member?(target)
          
          target_modes = channel.members[target]
          if adding
            target_modes << mode_char
          else
            target_modes.delete(mode_char)
          end
          
        else
          return false
        end
        
        # Send notifications
        targets = target ? [target] : [] of String
        @notification_service.notify_mode_change(channel_name, mode_string, nickname, targets)
        
        true
      end

      # Kick user from channel
      def kick_user(client : Client, channel_name : String, target_nickname : String, reason : String? = nil) : Bool
        return false unless nickname = client.nickname
        
        # Basic format validation
        unless channel_name.starts_with?("#") || channel_name.starts_with?("&")
          send_error(client, Numerics::ERR_BADCHANMASK, channel_name, "Wrong channel format")
          return false
        end
        
        channel = @channel_repository.get(channel_name)
        unless channel
          send_error(client, Numerics::ERR_NOSUCHCHANNEL, channel_name, "No such channel")
          return false
        end
        
        # Check if user is in channel and is operator
        unless channel.has_member?(nickname)
          send_error(client, Numerics::ERR_NOTONCHANNEL, channel_name, "You're not on that channel")
          return false
        end
        
        user_modes = channel.members[nickname]?
        unless user_modes && user_modes.includes?('o')
          send_error(client, Numerics::ERR_CHANOPRIVSNEEDED, channel_name, "You're not an operator")
          return false
        end
        
        # Check if target is in channel
        unless channel.has_member?(target_nickname)
          send_error(client, Numerics::ERR_NOSUCHNICK, target_nickname, "No such nick")
          return false
        end
        
        # Remove target from channel
        channel.remove_member(target_nickname)
        
        # Send notifications
        @notification_service.notify_user_kicked(channel_name, target_nickname, nickname, reason)
        
        true
      end

      private def validate_join_permissions(client : Client, channel : Domain::Channel, password : String?) : Bool
        return false unless nickname = client.nickname
        
        # Invite only?
        if channel.is_invite_only? && !channel.is_invited?(nickname)
          send_error(client, Numerics::ERR_INVITEONLYCHAN, channel.name, "Channel is invite only")
          return false
        end
        
        # Channel key/password?
        unless channel.password_matches?(password)
          send_error(client, Numerics::ERR_BADCHANNELKEY, channel.name, "Channel has a password")
          return false
        end
        
        # User limit check
        if channel.is_full?
          send_error(client, Numerics::ERR_CHANNELISFULL, channel.name, "Channel is full")
          return false
        end
        
        # Ban checking
        if hostmask = client.hostmask
          if channel.is_banned?(hostmask)
            send_error(client, Numerics::ERR_BANNEDFROMCHAN, channel.name, "You are banned from this channel")
            return false
          end
        end
        
        true
      end

      private def normalize_channel_name(name : String) : String
        name.starts_with?('#') || name.starts_with?('&') ? name : "##{name}"
      end
    end
  end
end