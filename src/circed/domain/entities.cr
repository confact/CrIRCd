# Core domain entities for the IRC server

module Circed
  module Domain
    record BanMatchContext,
      nickname : String,
      username : String,
      hostname : String,
      realname : String,
      hostmask : String,
      channels : Array(String)

    # Domain model for IRC users
    class User
      property nickname : String
      property username : String
      property hostname : String
      property realname : String
      property servername : String
      property hopcount : Int32
      property modes : Set(Char)
      property away_message : String?
      property ping_time : Time?

      def initialize(@nickname : String, @username : String, @hostname : String,
                     @realname : String, @servername : String, @hopcount : Int32 = 0)
        @modes = Set(Char).new
      end

      def hostmask : String
        "#{@nickname}!#{@username}@#{@hostname}"
      end

      def server : String
        @servername
      end

      def local? : Bool
        @servername == "localhost" || @hopcount == 0
      end

      def away? : Bool
        !@away_message.nil?
      end
    end

    # Domain model for IRC channels
    class Channel
      property name : String
      property topic : String?
      property topic_set_by : String?
      property topic_set_at : Time?
      property created_at : Time
      property modes : Set(Char)
      property members : Hash(String, Set(Char)) # nickname -> user modes
      property invite_list : Array(String)
      property ban_list : Array(String)

      # Private properties with public accessors
      @password : String?
      @user_limit : Int32?

      def initialize(@name : String)
        @modes = Set(Char).new
        @members = Hash(String, Set(Char)).new
        @invite_list = Array(String).new
        @ban_list = Array(String).new
        @created_at = Time.utc
      end

      def member_count : Int32
        @members.size
      end

      def has_member?(nickname : String) : Bool
        @members.has_key?(nickname)
      end

      def add_member(nickname : String, user_modes = Set(Char).new) : Void
        @members[nickname] = user_modes
      end

      def remove_member(nickname : String) : Bool
        !@members.delete(nickname).nil?
      end

      def user_modes(nickname : String) : Set(Char)
        @members[nickname]? || Set(Char).new
      end

      def empty? : Bool
        @members.empty?
      end

      def add_mode(mode : Char) : Void
        @modes << mode
      end

      def remove_mode(mode : Char) : Void
        @modes.delete(mode)
      end

      def has_mode?(mode : Char) : Bool
        @modes.includes?(mode)
      end

      # Password management
      def password=(new_password : String?)
        @password = new_password
        if new_password.nil?
          remove_mode('k')
        else
          add_mode('k')
        end
      end

      def password : String?
        @password
      end

      def has_password? : Bool
        !@password.nil? && has_mode?('k')
      end

      def password_matches?(provided_password : String?) : Bool
        return true unless has_password?
        return false if provided_password.nil?
        @password == provided_password
      end

      # User limit management
      def user_limit=(limit : Int32?)
        @user_limit = limit
        if limit.nil?
          remove_mode('l')
        else
          add_mode('l')
        end
      end

      def user_limit : Int32?
        @user_limit
      end

      def has_user_limit? : Bool
        !@user_limit.nil? && has_mode?('l')
      end

      def full? : Bool
        return false unless has_user_limit?
        limit = @user_limit
        return false if limit.nil?
        member_count >= limit
      end

      # Ban management
      def add_ban(ban_mask : String) : Void
        @ban_list << ban_mask unless @ban_list.includes?(ban_mask)
        add_mode('b')
      end

      def remove_ban(ban_mask : String) : Bool
        removed = @ban_list.delete(ban_mask)
        remove_mode('b') if @ban_list.empty?
        !removed.nil?
      end

      def banned?(hostmask : String) : Bool
        @ban_list.any? { |ban| matches_standard_ban_mask?(hostmask, ban) }
      end

      def banned?(context : BanMatchContext) : Bool
        @ban_list.any? { |ban| matches_ban_mask?(context, ban) }
      end

      private def matches_ban_mask?(context : BanMatchContext, ban_mask : String) : Bool
        if ban_mask.size >= 4 && (ban_mask[0] == '$' || ban_mask[0] == '~') && ban_mask[2] == ':'
          matches_extended_ban_mask?(context, ban_mask[1], ban_mask[3..-1])
        else
          matches_standard_ban_mask?(context.hostmask, ban_mask)
        end
      end

      private def matches_standard_ban_mask?(hostmask : String, ban_mask : String) : Bool
        wildcard_match?(ban_mask, hostmask)
      end

      private def matches_extended_ban_mask?(context : BanMatchContext, ban_type : Char, pattern : String) : Bool
        case ban_type.downcase
        when 'n'
          wildcard_match?(pattern, context.nickname)
        when 'u'
          wildcard_match?(pattern, context.username)
        when 'h'
          wildcard_match?(pattern, context.hostname)
        when 'r'
          wildcard_match?(pattern, context.realname)
        when 'j'
          context.channels.any? { |channel_name| wildcard_match?(pattern, channel_name) }
        when 'x'
          wildcard_match?(pattern, "#{context.hostmask}##{context.realname}")
        else
          false
        end
      end

      private def wildcard_match?(pattern : String, value : String) : Bool
        pattern_index = 0
        value_index = 0
        star_index = -1
        backtrack_value_index = 0

        while value_index < value.bytesize
          if pattern_index < pattern.bytesize &&
             wildcard_byte_matches?(pattern.byte_at(pattern_index), value.byte_at(value_index))
            pattern_index += 1
            value_index += 1
          elsif pattern_index < pattern.bytesize && pattern.byte_at(pattern_index) == '*'.ord.to_u8
            star_index = pattern_index
            backtrack_value_index = value_index
            pattern_index += 1
          elsif star_index >= 0
            pattern_index = star_index + 1
            backtrack_value_index += 1
            value_index = backtrack_value_index
          else
            return false
          end
        end

        while pattern_index < pattern.bytesize && pattern.byte_at(pattern_index) == '*'.ord.to_u8
          pattern_index += 1
        end

        pattern_index == pattern.bytesize
      end

      private def wildcard_byte_matches?(pattern_byte : UInt8, value_byte : UInt8) : Bool
        pattern_byte == '?'.ord.to_u8 || ascii_downcase(pattern_byte) == ascii_downcase(value_byte)
      end

      private def ascii_downcase(byte : UInt8) : UInt8
        value = byte.to_i
        return (value + 32).to_u8 if value >= 65 && value <= 90

        byte
      end

      # Invite management
      def add_invite(nickname : String) : Void
        @invite_list << nickname unless @invite_list.includes?(nickname)
      end

      def remove_invite(nickname : String) : Bool
        !@invite_list.delete(nickname).nil?
      end

      def invited?(nickname : String) : Bool
        @invite_list.includes?(nickname)
      end

      def invite_only? : Bool
        has_mode?('i')
      end

      def secret? : Bool
        has_mode?('s')
      end

      def private? : Bool
        has_mode?('p')
      end
    end

    # Domain model for IRC servers
    class Server
      property name : String
      property hostname : String
      property description : String
      property hopcount : Int32
      property user_count : Int32
      property operator_count : Int32
      property unknown_connections : Int32
      property channels_formed : Int32
      property link_server : LinkServer?
      property token : String?
      property ping_time : Time?

      def initialize(@name : String, @hostname : String, @description : String, @hopcount : Int32 = 0)
        @user_count = 0
        @operator_count = 0
        @unknown_connections = 0
        @channels_formed = 0
      end

      def local? : Bool
        @hopcount == 0
      end
    end

    # Network split tracking
    class NetworkSplit
      property? processed : Bool
      property split_server : String
      property split_time : Time
      property affected_servers : Array(String)
      property affected_users : Array(String)

      def initialize(@split_server : String)
        @split_time = Time.utc
        @affected_servers = Array(String).new
        @affected_users = Array(String).new
        @processed = false
      end
    end
  end
end
