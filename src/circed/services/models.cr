require "json"
require "crypto/bcrypt"

module Circed::Services
  # Channel access levels
  enum AccessLevel
    # No access
    None = 0
    # Voice (+v)
    Voice = 1
    # Half-op (+h) - some networks support this
    HalfOp = 2
    # Operator (+o)
    Operator = 3
    # Super operator (+a) - admin
    Admin = 4
    # Founder (+q) - owner
    Founder = 5

    def to_mode_char
      case self
      when .voice?
        'v'
      when .half_op?
        'h'
      when .operator?
        'o'
      when .admin?
        'a'
      when .founder?
        'q'
      else
        ' '
      end
    end
  end

  # Registered channel information
  struct RegisteredChannel
    include JSON::Serializable

    getter id : Int32
    getter channel_name : String
    getter founder : String
    getter registered_at : Time
    getter topic : String?
    getter modes : String
    getter access_list : Array(ChannelAccess)
    getter last_used : Time

    def initialize(@id : Int32, @channel_name : String, @founder : String,
                   @registered_at : Time, @topic : String?, @modes : String,
                   access_list_json : String, @last_used : Time)
      @access_list = begin
        Array(ChannelAccess).from_json(access_list_json)
      rescue JSON::ParseException
        [] of ChannelAccess
      end
    end

    def has_access?(nickname : String, level : AccessLevel) : Bool
      user_access = @access_list.find { |access| access.nickname.downcase == nickname.downcase }
      return false unless user_access
      user_access.access_level >= level
    end

    def get_access_level(nickname : String) : AccessLevel
      user_access = @access_list.find { |access| access.nickname.downcase == nickname.downcase }
      user_access ? user_access.access_level : AccessLevel::None
    end
  end

  # Channel access entry
  struct ChannelAccess
    include JSON::Serializable

    getter id : Int32
    getter channel_name : String
    getter nickname : String
    getter access_level : AccessLevel
    getter added_by : String
    getter added_at : Time

    def initialize(@id : Int32, @channel_name : String, @nickname : String,
                   access_level : Int32, @added_by : String, @added_at : Time)
      @access_level = AccessLevel.from_value(access_level)
    end
  end

  # Registered user information
  struct RegisteredUser
    include JSON::Serializable

    getter id : Int32
    getter nickname : String
    getter password_hash : String
    getter email : String?
    getter registered_at : Time
    getter last_seen : Time
    getter flags : Array(String)

    def initialize(@id : Int32, @nickname : String, @password_hash : String,
                   @email : String?, @registered_at : Time, @last_seen : Time,
                   flags_json : String)
      @flags = begin
        Array(String).from_json(flags_json)
      rescue JSON::ParseException
        [] of String
      end
    end

    def check_password(password : String) : Bool
      Crypto::Bcrypt::Password.new(@password_hash).verify(password)
    end

    def has_flag?(flag : String) : Bool
      @flags.includes?(flag)
    end
  end

  # User alias (alternative nicknames)
  struct UserAlias
    getter id : Int32
    getter nickname : String
    getter alias : String
    getter added_at : Time

    def initialize(@id : Int32, @nickname : String, @alias : String, @added_at : Time)
    end
  end
end
