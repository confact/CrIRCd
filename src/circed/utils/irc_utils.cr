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
        BANNED_FROM_CHANNEL    = "Cannot join channel (+b)"
        CHANNEL_HAS_PASSWORD   = "Channel has a password"
        CHANNEL_IS_FULL        = "Channel is full"
        UNKNOWN_COMMAND        = "Unknown command"
        USER_ON_CHANNEL        = "User is already in channel"
        USERS_DONT_MATCH       = "Cannot change mode for other users"
      end

      # Channel validation utilities
      def self.valid_channel_name?(channel_name : String) : Bool
        return false if channel_name.empty?
        return false if channel_name.bytesize > 50
        return false unless "#&+!".includes?(channel_name[0])
        return false if channel_name.includes?(' ') || channel_name.includes?(',') || channel_name.includes?('\a')
        return false if channel_name.includes?('\0') || channel_name.includes?('\r') || channel_name.includes?('\n')

        true
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

        nickname.each_char_with_index do |char, index|
          if index == 0
            return false unless char.ascii_letter? || "_[]{}\\`|^".includes?(char)
          else
            return false unless char.ascii_alphanumeric? || "-_[]{}\\`|^".includes?(char)
          end
        end

        true
      end

      def self.mode_string(modes : Set(Char)) : String
        String.build do |io|
          io << '+'
          modes.each do |mode|
            io << mode
          end
        end
      end

      def self.mode_set(modes : String) : Set(Char)
        result = Set(Char).new
        modes.each_char { |mode| result << mode unless mode == '+' || mode == '-' }
        result
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
        send_error(sender, Numerics::ERR_NOTREGISTERED, ErrorMessages::NOT_REGISTERED)
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

      def self.format_hostmask(nickname : String, username : String, hostname : String) : String
        capacity = nickname.size + username.size + hostname.size + 2
        String.build(capacity: capacity) do |io|
          io << nickname << '!' << username << '@' << hostname
        end
      end

      def self.split_list_param(param : String) : Array(String)
        param.split(',', remove_empty: true)
      end

      def self.split_list_param(param : String?) : Array(String)
        return [] of String unless param

        split_list_param(param)
      end

      def self.each_list_param(param : String, & : String ->) : Nil
        param.split(',', remove_empty: true) { |item| yield item }
      end

      def self.trailing_param(params : Array(String), start_index : Int32, default = "") : String
        return default if start_index >= params.size

        String.build do |io|
          index = start_index
          while index < params.size
            io << ' ' if index > start_index
            param = params[index]
            if index == start_index && param.starts_with?(':')
              io.write(param.to_slice + 1)
            else
              io << param
            end
            index += 1
          end
        end
      end

      # Check if a user has a specific mode in a channel
      def self.user_has_channel_mode?(channel : Domain::Channel, nickname : String, mode : Char) : Bool
        user_modes = channel.member_modes?(nickname)
        user_modes.try(&.includes?(mode)) || false
      end

      # Check if user is operator in channel
      def self.user_is_operator?(channel : Domain::Channel, nickname : String) : Bool
        user_has_channel_mode?(channel, nickname, 'o')
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
