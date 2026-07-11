# Core domain entities for the IRC server
require "yaml"

module Circed
  module Domain
    module Wildcard
      STAR_BYTE     = '*'.ord.to_u8
      QUESTION_BYTE = '?'.ord.to_u8

      def self.match?(pattern : String, value : String) : Bool
        pattern_index = 0
        value_index = 0
        star_index = -1
        backtrack_value_index = 0

        while value_index < value.bytesize
          if pattern_index < pattern.bytesize &&
             wildcard_byte_matches?(pattern.byte_at(pattern_index), value.byte_at(value_index))
            pattern_index += 1
            value_index += 1
          elsif pattern_index < pattern.bytesize && pattern.byte_at(pattern_index) == STAR_BYTE
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

        while pattern_index < pattern.bytesize && pattern.byte_at(pattern_index) == STAR_BYTE
          pattern_index += 1
        end

        pattern_index == pattern.bytesize
      end

      private def self.wildcard_byte_matches?(pattern_byte : UInt8, value_byte : UInt8) : Bool
        pattern_byte == QUESTION_BYTE || CaseMapping.fold(pattern_byte) == CaseMapping.fold(value_byte)
      end
    end

    record BanMatchContext,
      nickname : String,
      username : String,
      hostname : String,
      ip_address : String,
      realname : String,
      hostmask : String,
      channels : Array(String)

    struct LineBan
      include YAML::Serializable

      KLINE = "KLINE"
      GLINE = "GLINE"
      ZLINE = "ZLINE"
      TYPES = {KLINE, GLINE, ZLINE}

      getter type : String
      getter mask : String
      getter reason : String
      getter set_by : String
      getter set_at : Time
      getter expires_at : Time?

      def initialize(type : String, mask : String, reason : String, set_by : String, @set_at : Time = Time.utc, @expires_at : Time? = nil)
        @type = type.upcase
        @mask = mask
        @reason = reason
        @set_by = set_by
      end

      def self.key(type : String, mask : String) : String
        "#{type.upcase}:#{mask}"
      end

      def key : String
        self.class.key(@type, @mask)
      end

      def expired?(now : Time = Time.utc) : Bool
        expires_at = @expires_at
        !expires_at.nil? && expires_at <= now
      end

      def matches?(context : BanMatchContext) : Bool
        case @type
        when ZLINE
          ip_matches?(context.ip_address)
        when KLINE, GLINE
          Wildcard.match?(@mask, context.hostmask)
        else
          false
        end
      end

      def server_message : String
        String.build do |io|
          io << @type << ' ' << @mask << ' ' << (expires_at.try(&.to_unix) || 0_i64)
          io << ' ' << @set_by << " :" << @reason
        end
      end

      private def ip_matches?(ip_address : String) : Bool
        if slash_index = @mask.index('/')
          return cidr_matches?(ip_address, slash_index)
        end

        Wildcard.match?(@mask, ip_address)
      end

      private def cidr_matches?(ip_address : String, slash_index : Int32) : Bool
        prefix = cidr_prefix(slash_index + 1)
        return false unless prefix && prefix <= 32
        return false unless network_value = ipv4_to_u32(@mask, slash_index)
        return false unless ip_value = ipv4_to_u32(ip_address)

        mask = prefix == 0 ? 0_u32 : UInt32::MAX << (32 - prefix)
        (network_value & mask) == (ip_value & mask)
      end

      private def cidr_prefix(start_index : Int32) : Int32?
        return nil if start_index >= @mask.bytesize

        prefix = 0
        index = start_index
        while index < @mask.bytesize
          byte = @mask.byte_at(index)
          digit = ascii_digit_value(byte)
          return nil unless digit

          prefix = prefix * 10 + digit
          index += 1
        end
        prefix
      end

      private def ipv4_to_u32(ip_address : String, end_index : Int32 = ip_address.bytesize) : UInt32?
        value = 0_u32
        octet = 0
        octet_digits = 0
        octet_count = 0
        index = 0

        while index < end_index
          byte = ip_address.byte_at(index)
          if digit = ascii_digit_value(byte)
            return nil if octet_digits == 3

            octet = octet * 10 + digit
            return nil if octet > 255

            octet_digits += 1
          elsif byte == '.'.ord.to_u8
            return nil if octet_digits == 0 || octet_count == 3

            value = (value << 8) | octet.to_u32
            octet = 0
            octet_digits = 0
            octet_count += 1
          else
            return nil
          end

          index += 1
        end

        return nil unless octet_digits > 0 && octet_count == 3

        (value << 8) | octet.to_u32
      end

      private def ascii_digit_value(byte : UInt8) : Int32?
        return unless byte >= '0'.ord.to_u8 && byte <= '9'.ord.to_u8

        byte.to_i - '0'.ord
      end
    end

    # Domain model for IRC users
    class User
      GLOBAL_OPERATOR_MODE = 'o'
      LOCAL_OPERATOR_MODE  = 'O'
      OPERATOR_MODES       = {GLOBAL_OPERATOR_MODE, LOCAL_OPERATOR_MODE}

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

      def ban_match_context(ip_address : String, channels : Array(String)) : BanMatchContext
        BanMatchContext.new(
          @nickname,
          @username,
          @hostname,
          ip_address,
          @realname,
          hostmask,
          channels
        )
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

      def irc_operator? : Bool
        OPERATOR_MODES.any? { |mode| @modes.includes?(mode) }
      end

      def global_irc_operator? : Bool
        @modes.includes?(GLOBAL_OPERATOR_MODE)
      end
    end

    # Domain model for IRC channels
    class Channel
      SIMPLE_MODES = {'i', 'm', 'n', 't', 's', 'p'}
      USER_MODES   = {'o', 'h', 'v'}

      property name : String
      property topic : String?
      property topic_set_by : String?
      property topic_set_at : Time?
      property created_at : Time
      property modes : Set(Char)
      property members : Hash(String, Set(Char)) # nickname -> user modes
      property invite_list : Set(String)
      property ban_list : Set(String)

      # Private properties with public accessors
      @password : String?
      @user_limit : Int32?
      @member_names : Hash(String, String)

      def initialize(@name : String)
        @modes = Set(Char).new
        @members = Hash(String, Set(Char)).new
        @member_names = Hash(String, String).new
        @invite_list = Set(String).new
        @ban_list = Set(String).new
        @created_at = Time.unix(Time.utc.to_unix)
      end

      def member_count : Int32
        @members.size
      end

      def has_member?(nickname : String) : Bool
        @member_names.has_key?(CaseMapping.normalize(nickname))
      end

      def add_member(nickname : String, user_modes = Set(Char).new) : Nil
        key = CaseMapping.normalize(nickname)
        if existing_name = @member_names[key]?
          @members[existing_name] = user_modes
          return
        end

        @member_names[key] = nickname
        @members[nickname] = user_modes
      end

      def remove_member(nickname : String) : Bool
        return false unless display_name = @member_names.delete(CaseMapping.normalize(nickname))

        !@members.delete(display_name).nil?
      end

      def member_modes?(nickname : String) : Set(Char)?
        return unless display_name = @member_names[CaseMapping.normalize(nickname)]?

        @members[display_name]?
      end

      def rename_member(old_nickname : String, new_nickname : String) : Bool
        return false unless modes = member_modes?(old_nickname)

        remove_member(old_nickname)
        add_member(new_nickname, modes)
        true
      end

      def self.member_prefix(modes : Set(Char)) : Char?
        return '@' if modes.includes?('o')
        return '%' if modes.includes?('h')
        return '+' if modes.includes?('v')
      end

      def empty? : Bool
        @members.empty?
      end

      def add_mode(mode : Char) : Nil
        @modes << mode
      end

      def remove_mode(mode : Char) : Nil
        @modes.delete(mode)
      end

      def has_mode?(mode : Char) : Bool
        @modes.includes?(mode)
      end

      def apply_modes(mode_string : String, params : Array(String), parameter_index : Int32 = 0) : NamedTuple(modes: String, parameter_count: Int32)
        adding = true
        first_parameter = parameter_index
        last_sign = '\0'
        applied_modes = String.build do |io|
          mode_string.each_char do |mode|
            case mode
            when '+'
              adding = true
            when '-'
              adding = false
            else
              parameter = nil
              if mode_needs_parameter?(mode, adding)
                parameter = params[parameter_index]?
                parameter_index += 1
                next unless parameter
              end
              next unless apply_mode(mode, adding, parameter)

              sign = adding ? '+' : '-'
              io << sign if sign != last_sign
              io << mode
              last_sign = sign
            end
          end
        end

        {modes: applied_modes, parameter_count: parameter_index - first_parameter}
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
      def add_ban(ban_mask : String) : Nil
        @ban_list << ban_mask
        add_mode('b')
      end

      def remove_ban(ban_mask : String) : Bool
        removed = @ban_list.delete(ban_mask)
        remove_mode('b') if @ban_list.empty?
        removed
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
        Wildcard.match?(ban_mask, hostmask)
      end

      private def matches_extended_ban_mask?(context : BanMatchContext, ban_type : Char, pattern : String) : Bool
        case ban_type.downcase
        when 'n'
          Wildcard.match?(pattern, context.nickname)
        when 'u'
          Wildcard.match?(pattern, context.username)
        when 'h'
          Wildcard.match?(pattern, context.hostname)
        when 'r'
          Wildcard.match?(pattern, context.realname)
        when 'j'
          context.channels.any? { |channel_name| Wildcard.match?(pattern, channel_name) }
        when 'x'
          Wildcard.match?(pattern, "#{context.hostmask}##{context.realname}")
        else
          false
        end
      end

      # Invite management
      def add_invite(nickname : String) : Nil
        @invite_list << CaseMapping.normalize(nickname)
      end

      def remove_invite(nickname : String) : Bool
        @invite_list.delete(CaseMapping.normalize(nickname))
      end

      def invited?(nickname : String) : Bool
        @invite_list.includes?(CaseMapping.normalize(nickname))
      end

      def invite_only? : Bool
        has_mode?('i')
      end

      private def mode_needs_parameter?(mode : Char, adding : Bool) : Bool
        USER_MODES.includes?(mode) || mode == 'b' || adding && (mode == 'k' || mode == 'l')
      end

      private def apply_mode(mode : Char, adding : Bool, parameter : String?) : Bool
        case
        when SIMPLE_MODES.includes?(mode)
          apply_simple_mode(mode, adding)
        when USER_MODES.includes?(mode)
          apply_user_mode(mode, adding, parameter)
        when mode == 'b'
          apply_ban_mode(adding, parameter)
        when mode == 'k'
          apply_key_mode(adding, parameter)
        when mode == 'l'
          apply_limit_mode(adding, parameter)
        else
          false
        end
      end

      private def apply_simple_mode(mode : Char, adding : Bool) : Bool
        if adding
          remove_mode('s') if mode == 'p'
          remove_mode('p') if mode == 's'
        end
        adding ? add_mode(mode) : remove_mode(mode)
        true
      end

      private def apply_user_mode(mode : Char, adding : Bool, nickname : String?) : Bool
        return false unless nickname
        return false unless modes = member_modes?(nickname)

        adding ? modes << mode : modes.delete(mode)
        true
      end

      private def apply_ban_mode(adding : Bool, mask : String?) : Bool
        return false unless mask

        adding ? add_ban(mask) : remove_ban(mask)
        true
      end

      private def apply_key_mode(adding : Bool, key : String?) : Bool
        return false if adding && key.nil?

        self.password = adding ? key : nil
        true
      end

      private def apply_limit_mode(adding : Bool, parameter : String?) : Bool
        unless adding
          self.user_limit = nil
          return true
        end

        return false unless limit = parameter.try(&.to_i?)
        return false unless limit > 0

        self.user_limit = limit
        true
      end

      def secret? : Bool
        has_mode?('s')
      end

      def visible_to?(nickname : String?) : Bool
        return true unless secret? || private?

        nickname ? has_member?(nickname) : false
      end

      def private? : Bool
        has_mode?('p')
      end
    end
  end
end
