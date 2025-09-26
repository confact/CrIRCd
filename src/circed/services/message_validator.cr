module Circed
  module Services
    # IRC message validation service implementing RFC 1459 compliance
    class MessageValidator
      # RFC 1459 states messages should not exceed 512 characters including CR-LF
      MAX_MESSAGE_LENGTH = 512
      MAX_NICK_LENGTH = 30
      MAX_CHANNEL_NAME_LENGTH = 200
      MAX_TOPIC_LENGTH = 307  # 512 - command overhead
      MAX_KICK_REASON_LENGTH = 307

      # Validate raw IRC message before parsing
      def self.validate_raw_message(raw_message : String) : Bool
        return false if raw_message.bytesize > MAX_MESSAGE_LENGTH
        return false if raw_message.empty?
        
        # Check for required CR-LF termination (FastIRC handles this)
        true
      end

      # Validate IRC nickname according to RFC 1459
      def self.validate_nickname(nickname : String?) : Bool
        return false unless nickname
        return false if nickname.empty?
        return false if nickname.size > MAX_NICK_LENGTH

        # IRC nickname rules: start with letter, contain letters/numbers/special chars
        # Allowed: a-z, A-Z, 0-9, -, [, ], \, `, ^, {, }, _, |
        nickname.matches?(/^[a-zA-Z][a-zA-Z0-9\-\[\]\\`^{}_\|]*$/)
      end

      # Validate IRC channel name according to RFC 1459
      def self.validate_channel_name(name : String?) : Bool
        return false unless name
        return false if name.empty?
        return false unless name.starts_with?('#') || name.starts_with?('&')
        return false if name.size > MAX_CHANNEL_NAME_LENGTH
        return false if name.includes?(' ') || name.includes?('\0') || name.includes?('\r') || name.includes?('\n')
        return false if name.includes?(',') || name.includes?('\a') # comma is list separator, bell is control-G
        true
      end

      # Validate username according to RFC 1459
      def self.validate_username(username : String?) : Bool
        return false unless username
        return false if username.empty?
        return false if username.size > 32

        # Username rules: no spaces or special IRC characters
        !username.includes?(' ') && !username.includes?('@') && !username.includes?('!')
      end

      # Validate topic length
      def self.validate_topic(topic : String?) : Bool
        return true if topic.nil? || topic.empty?
        topic.size <= MAX_TOPIC_LENGTH
      end

      # Validate kick reason length
      def self.validate_kick_reason(reason : String?) : Bool
        return true if reason.nil? || reason.empty?
        reason.size <= MAX_KICK_REASON_LENGTH
      end

      # Validate away message
      def self.validate_away_message(message : String?) : Bool
        return true if message.nil? || message.empty?
        message.size <= MAX_TOPIC_LENGTH  # Use same limit as topic
      end

      # Validate mode string
      def self.validate_mode_string(mode_string : String?) : Bool
        return false unless mode_string
        return false if mode_string.empty?
        return false if mode_string.size > 100  # Reasonable limit

        # Mode string should start with + or - and contain valid mode characters
        mode_string.matches?(/^[+\-][a-zA-Z0-9]*$/)
      end

      # Validate PRIVMSG/NOTICE message
      def self.validate_message_text(message : String?) : Bool
        return false unless message
        return false if message.empty?
        return false if message.size > (MAX_MESSAGE_LENGTH - 100)  # Leave room for command overhead

        # Don't allow null bytes or other control characters except common ones
        !message.includes?('\0')
      end

      # Validate server name
      def self.validate_server_name(server_name : String?) : Bool
        return false unless server_name
        return false if server_name.empty?
        return false if server_name.size > 63  # DNS hostname limit

        # Basic hostname validation - alphanumeric, dots, hyphens
        server_name.matches?(/^[a-zA-Z0-9\-\.]+$/)
      end

      # Validate IRC command parameters count
      def self.validate_command_params(command : String, params : Array(String)) : Bool
        case command.upcase
        when "NICK"
          params.size == 1
        when "USER"
          params.size == 4
        when "JOIN"
          params.size >= 1 && params.size <= 2
        when "PART"
          params.size >= 1 && params.size <= 2
        when "PRIVMSG", "NOTICE"
          params.size == 2
        when "TOPIC"
          params.size >= 1 && params.size <= 2
        when "KICK"
          params.size >= 2 && params.size <= 3
        when "MODE"
          params.size >= 1
        when "WHOIS"
          params.size >= 1 && params.size <= 2
        when "QUIT"
          params.size <= 1
        when "INVITE"
          params.size == 2
        when "AWAY"
          params.size <= 1
        when "NAMES"
          params.size <= 1
        when "WHO"
          params.size <= 1
        else
          true  # Allow unknown commands to pass through
        end
      end

      # Comprehensive validation for IRC commands
      def self.validate_irc_command(command : String, params : Array(String)) : String?
        # Check parameter count
        unless validate_command_params(command, params)
          return "Invalid parameter count for #{command}"
        end

        case command.upcase
        when "NICK"
          unless validate_nickname(params[0])
            return "Invalid nickname format"
          end
        when "JOIN"
          unless validate_channel_name(params[0])
            return "Invalid channel name"
          end
        when "PART"
          unless validate_channel_name(params[0])
            return "Invalid channel name"
          end
        when "PRIVMSG", "NOTICE"
          target = params[0]
          message = params[1]
          
          # Target can be channel or nickname
          unless validate_channel_name(target) || validate_nickname(target)
            return "Invalid target"
          end
          
          unless validate_message_text(message)
            return "Invalid message content"
          end
        when "TOPIC"
          unless validate_channel_name(params[0])
            return "Invalid channel name"
          end
          
          if params.size > 1 && !validate_topic(params[1])
            return "Topic too long"
          end
        when "KICK"
          unless validate_channel_name(params[0])
            return "Invalid channel name"
          end
          
          unless validate_nickname(params[1])
            return "Invalid nickname"
          end
          
          if params.size > 2 && !validate_kick_reason(params[2])
            return "Kick reason too long"
          end
        when "MODE"
          target = params[0]
          
          # Target can be channel or nickname
          unless validate_channel_name(target) || validate_nickname(target)
            return "Invalid target"
          end
          
          if params.size > 1 && !validate_mode_string(params[1])
            return "Invalid mode string"
          end
        when "WHOIS"
          unless validate_nickname(params[0])
            return "Invalid nickname"
          end
        when "INVITE"
          unless validate_nickname(params[0])
            return "Invalid nickname"
          end
          
          unless validate_channel_name(params[1])
            return "Invalid channel name"
          end
        when "AWAY"
          if params.size > 0 && !validate_away_message(params[0])
            return "Away message too long"
          end
        end

        nil  # No validation errors
      end
    end
  end
end 