module Circed
  module Utils
    # Consolidated IRC utilities to eliminate duplicate validation and helper code
    module IrcUtils
      # Common IRC error messages to avoid string duplication
      module ErrorMessages
        NO_SUCH_NICK           = "No such nick"
        NO_SUCH_CHANNEL        = "No such channel"
        NOT_ON_CHANNEL         = "You're not on that channel"
        NOT_CHANNEL_OPERATOR   = "You're not channel operator"
        BAD_CHANNEL_MASK       = "Bad Channel Mask"
        WRONG_CHANNEL_FORMAT   = "Wrong channel format"
        NOT_REGISTERED         = "You have not registered"
        NICKNAME_IN_USE        = "Nickname is already in use"
        CANNOT_SEND_TO_CHANNEL = "Cannot send to channel"
        INVITE_ONLY_CHANNEL    = "Cannot join channel (+i)"
        BANNED_FROM_CHANNEL    = "You are banned from this channel"
        CHANNEL_HAS_PASSWORD   = "Channel has a password"
        CHANNEL_IS_FULL        = "Channel is full"
        UNKNOWN_COMMAND        = "Unknown command"
        USER_ON_CHANNEL        = "User is already in channel"
        USERS_DONT_MATCH       = "Cannot change mode for other users"
      end

      # Channel validation utilities
      def self.valid_channel_name?(channel_name : String) : Bool
        return false if channel_name.empty?
        channel_name.starts_with?('#') || channel_name.starts_with?('&')
      end

      # Validate channel name and send error if invalid
      def self.validate_channel_name(sender : Client, channel_name : String) : Bool
        if valid_channel_name?(channel_name)
          true
        else
          send_channel_error(sender, channel_name)
          false
        end
      end

      # Nickname validation utilities
      def self.valid_nickname?(nickname : String) : Bool
        return false if nickname.empty?
        return false if nickname.size > 30 # RFC limit

        # First character must be letter or special char
        first = nickname[0]
        return false unless first.ascii_letter? || "_[]{}\\`|".includes?(first)

        # Rest can be letters, digits, or special chars
        nickname[1..].each_char do |char|
          return false unless char.ascii_alphanumeric? || "-_[]{}\\`|".includes?(char)
        end

        true
      end

      # User mode validation
      def self.valid_user_mode?(mode : Char) : Bool
        "iwo".includes?(mode)
      end

      # Channel mode validation
      def self.valid_channel_mode?(mode : Char) : Bool
        "ontpsimklv".includes?(mode)
      end

      # Common error sending helpers
      def self.send_no_such_nick_error(sender : Client, nickname : String)
        send_error(sender, Numerics::ERR_NOSUCHNICK, nickname, ErrorMessages::NO_SUCH_NICK)
      end

      def self.send_no_such_channel_error(sender : Client, channel_name : String)
        send_error(sender, Numerics::ERR_NOSUCHCHANNEL, channel_name, ErrorMessages::NO_SUCH_CHANNEL)
      end

      def self.send_not_on_channel_error(sender : Client, channel_name : String)
        send_error(sender, Numerics::ERR_NOTONCHANNEL, channel_name, ErrorMessages::NOT_ON_CHANNEL)
      end

      def self.send_not_operator_error(sender : Client, channel_name : String)
        send_error(sender, Numerics::ERR_CHANOPRIVSNEEDED, channel_name, ErrorMessages::NOT_CHANNEL_OPERATOR)
      end

      def self.send_channel_error(sender : Client, channel_name : String)
        send_error(sender, Numerics::ERR_BADCHANMASK, channel_name, ErrorMessages::BAD_CHANNEL_MASK)
      end

      def self.send_not_registered_error(sender : Client)
        send_error(sender, Numerics::ERR_NOTREGISTERED, "*", ErrorMessages::NOT_REGISTERED)
      end

      def self.send_nickname_in_use_error(sender : Client, nickname : String)
        send_error(sender, Numerics::ERR_NICKNAMEINUSE, nickname, ErrorMessages::NICKNAME_IN_USE)
      end

      def self.send_user_on_channel_error(sender : Client, channel_name : String)
        send_error(sender, Numerics::ERR_USERONCHANNEL, channel_name, ErrorMessages::USER_ON_CHANNEL)
      end

      def self.send_users_dont_match_error(sender : Client)
        send_error(sender, Numerics::ERR_USERSDONTMATCH, ErrorMessages::USERS_DONT_MATCH)
      end

      def self.send_cannot_send_to_channel_error(sender : Client, channel_name : String)
        send_error(sender, Numerics::ERR_CANNOTSENDTOCHAN, channel_name, ErrorMessages::CANNOT_SEND_TO_CHANNEL)
      end

      def self.send_invite_only_error(sender : Client, channel_name : String)
        send_error(sender, Numerics::ERR_INVITEONLYCHAN, channel_name, ErrorMessages::INVITE_ONLY_CHANNEL)
      end

      def self.send_bad_channel_key_error(sender : Client, channel_name : String)
        send_error(sender, Numerics::ERR_BADCHANNELKEY, channel_name, ErrorMessages::CHANNEL_HAS_PASSWORD)
      end

      def self.send_channel_full_error(sender : Client, channel_name : String)
        send_error(sender, Numerics::ERR_CHANNELISFULL, channel_name, ErrorMessages::CHANNEL_IS_FULL)
      end

      def self.send_banned_from_channel_error(sender : Client, channel_name : String)
        send_error(sender, Numerics::ERR_BANNEDFROMCHAN, channel_name, ErrorMessages::BANNED_FROM_CHANNEL)
      end

      # Format hostmask efficiently (moved from UnifiedMessaging)
      def self.format_hostmask(nickname : String, username : String, hostname : String) : String
        capacity = nickname.size + username.size + hostname.size + 2
        String.build(capacity: capacity) do |io|
          io << nickname << '!' << username << '@' << hostname
        end
      end

      # Extract channel name from IRC message parameter
      def self.extract_channel_name(param : String) : String?
        return nil if param.empty?

        # Handle comma-separated channel lists (take first one)
        channel = param.split(',').first?.try(&.strip)
        return nil unless channel && valid_channel_name?(channel)

        channel
      end

      # Extract nickname from hostmask
      def self.extract_nickname_from_hostmask(hostmask : String) : String?
        return nil if hostmask.empty?

        # Format: nick!user@host
        exclamation_pos = hostmask.index('!')
        return nil unless exclamation_pos

        nickname = hostmask[0...exclamation_pos]
        valid_nickname?(nickname) ? nickname : nil
      end

      # Check if a user has a specific mode in a channel
      def self.user_has_channel_mode?(channel : Domain::Channel, nickname : String, mode : Char) : Bool
        user_modes = channel.members[nickname]?
        user_modes && user_modes.includes?(mode)
      end

      # Check if user is operator in channel
      def self.user_is_operator?(channel : Domain::Channel, nickname : String) : Bool
        user_has_channel_mode?(channel, nickname, 'o')
      end

      # Check if user is voiced in channel
      def self.user_is_voiced?(channel : Domain::Channel, nickname : String) : Bool
        user_has_channel_mode?(channel, nickname, 'v')
      end

      # Check if user can modify channel (operator or higher)
      def self.user_can_modify_channel?(channel : Domain::Channel, nickname : String) : Bool
        user_is_operator?(channel, nickname)
      end

      # Common repository access helpers
      def self.user_repository
        Infrastructure::ServiceLocator.user_repository
      end

      def self.channel_repository
        Infrastructure::ServiceLocator.channel_repository
      end

      def self.server_repository
        Infrastructure::ServiceLocator.server_repository
      end

      # Delegate to unified messaging for error sending
      private def self.send_error(sender : Client, code : String, message : String)
        sender.send_message(Server.clean_name, code, sender.nickname || "*", ":#{message}")
      end

      private def self.send_error(sender : Client, code : String, item : String, message : String)
        sender.send_message(Server.clean_name, code, sender.nickname || "*", item, ":#{message}")
      end
    end
  end
end
