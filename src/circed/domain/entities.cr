# Domain entities representing core IRC concepts
module Circed
  module Domain
    # Represents a user in the IRC network
    class User
      property nickname : String
      property username : String
      property hostname : String
      property realname : String
      property server : String
      property hopcount : Int32
      property modes : Set(Char)
      property away_message : String?
      property channels : Set(String)
      property signon_time : Time
      property last_activity : Time

      def initialize(@nickname : String, @username : String, @hostname : String,
                     @realname : String, @server : String, @hopcount = 0)
        @modes = Set(Char).new
        @channels = Set(String).new
        @signon_time = Time.utc
        @last_activity = Time.utc
      end

      def hostmask : String
        "#{@nickname}!#{@username}@#{@hostname}"
      end

      def is_local? : Bool
        @hopcount == 0
      end

      def is_away? : Bool
        !@away_message.nil?
      end

      def update_activity
        @last_activity = Time.utc
      end
    end

    # Represents a channel in the IRC network
    class Channel
      property name : String
      property topic : String?
      property topic_set_by : String?
      property topic_set_at : Time?
      property modes : Set(Char)
      property members : Hash(String, Set(Char)) # nickname -> user modes in channel
      property created_at : Time
      property ban_list : Array(String)
      property invite_list : Array(String)
      property password : String?
      property user_limit : Int32?

      def initialize(@name : String)
        @modes = Set(Char).new
        @members = Hash(String, Set(Char)).new
        @created_at = Time.utc
        @ban_list = Array(String).new
        @invite_list = Array(String).new
        @password = nil
        @user_limit = nil
      end

      def add_member(nickname : String, user_modes = Set(Char).new)
        @members[nickname] = user_modes
      end

      def remove_member(nickname : String) : Bool
        @members.delete(nickname) != nil
      end

      def has_member?(nickname : String) : Bool
        @members.has_key?(nickname)
      end

      def is_empty? : Bool
        @members.empty?
      end

      def member_count : Int32
        @members.size
      end

      def operators : Array(String)
        @members.select { |_, modes| modes.includes?('o') }.keys
      end

      def voiced_users : Array(String)
        @members.select { |_, modes| modes.includes?('v') }.keys
      end

      # Password management
      def set_password(new_password : String?)
        @password = new_password
        if new_password
          @modes << 'k'
        else
          @modes.delete('k')
        end
      end

      def has_password? : Bool
        !@password.nil? && @modes.includes?('k')
      end

      def password_matches?(provided_password : String?) : Bool
        return true unless has_password?
        @password == provided_password
      end

      # User limit management
      def set_user_limit(limit : Int32?)
        @user_limit = limit
        if limit
          @modes << 'l'
        else
          @modes.delete('l')
        end
      end

      def has_user_limit? : Bool
        !@user_limit.nil? && @modes.includes?('l')
      end

      def is_full? : Bool
        return false unless has_user_limit?
        member_count >= @user_limit.not_nil!
      end

      # Ban management
      def add_ban(ban_mask : String)
        @ban_list << ban_mask unless @ban_list.includes?(ban_mask)
      end

      def remove_ban(ban_mask : String)
        @ban_list.delete(ban_mask)
      end

      def is_banned?(hostmask : String) : Bool
        @ban_list.any? { |ban| matches_ban_mask?(hostmask, ban) }
      end

      # Invite management
      def add_invite(nickname : String)
        @invite_list << nickname unless @invite_list.includes?(nickname)
      end

      def remove_invite(nickname : String)
        @invite_list.delete(nickname)
      end

      def is_invited?(nickname : String) : Bool
        @invite_list.includes?(nickname)
      end

      # Channel mode helpers
      def is_invite_only? : Bool
        @modes.includes?('i')
      end

      def is_secret? : Bool
        @modes.includes?('s')
      end

      def is_private? : Bool
        @modes.includes?('p')
      end

      private def matches_ban_mask?(hostmask : String, ban_mask : String) : Bool
        # Simple wildcard matching for ban masks
        # Convert IRC wildcard pattern to regex
        regex_pattern = ban_mask.gsub("*", ".*").gsub("?", ".")
        regex_pattern = "^#{regex_pattern}$"
        hostmask.matches?(Regex.new(regex_pattern, Regex::Options::IGNORE_CASE))
      end
    end

    # Represents a server in the IRC network
    class Server
      property name : String
      property description : String
      property hopcount : Int32
      property token : String?
      property link_server : LinkServer?
      property connected_at : Time
      property users : Set(String)
      property ping_time : Time?

      def initialize(@name : String, @description : String, @hopcount = 0, @token = nil, @link_server = nil)
        @connected_at = Time.utc
        @users = Set(String).new
      end

      def is_local? : Bool
        @hopcount == 0
      end

      def add_user(nickname : String)
        @users << nickname
      end

      def remove_user(nickname : String)
        @users.delete(nickname)
      end

      def user_count : Int32
        @users.size
      end
    end

    # Represents an IRC message with context
    class Message
      property raw_message : FastIRC::Message
      property source : Core::MessageSource
      property timestamp : Time
      property processed : Bool

      def initialize(@raw_message : FastIRC::Message, @source : Core::MessageSource, @timestamp = Time.utc)
        @processed = false
      end

      def command : String
        @raw_message.command
      end

      def params : Array(String)
        @raw_message.params
      end

      def prefix : FastIRC::Prefix?
        @raw_message.prefix
      end

      def mark_processed
        @processed = true
      end
    end

    # Message sources
    class ClientSource < Core::MessageSource
      property client : Client

      def initialize(@client : Client)
      end

      def identifier : String
        @client.nickname || "unknown"
      end

      def type : Core::SourceType
        Core::SourceType::LocalClient
      end
    end

    class ServerSource < Core::MessageSource
      property server : Server

      def initialize(@server : Server)
      end

      def identifier : String
        @server.name
      end

      def type : Core::SourceType
        @server.is_local? ? Core::SourceType::LocalServer : Core::SourceType::RemoteServer
      end
    end

    # Events for the notification system
    class UserJoinedEvent < Core::NotificationEvent
      property user : String
      property channel : String

      def initialize(@user : String, @channel : String)
      end

      def event_type : String
        "user.joined"
      end

      def data : Hash(String, String)
        {"user" => @user, "channel" => @channel}
      end
    end

    class UserPartedEvent < Core::NotificationEvent
      property user : String
      property channel : String
      property reason : String?

      def initialize(@user : String, @channel : String, @reason = nil)
      end

      def event_type : String
        "user.parted"
      end

      def data : Hash(String, String)
        result = {"user" => @user, "channel" => @channel}
        result["reason"] = @reason if @reason
        result
      end
    end

    class UserQuitEvent < Core::NotificationEvent
      property user : String
      property reason : String?

      def initialize(@user : String, @reason = nil)
      end

      def event_type : String
        "user.quit"
      end

      def data : Hash(String, String)
        result = {"user" => @user}
        result["reason"] = @reason if @reason
        result
      end
    end

    class ServerDisconnectedEvent < Core::NotificationEvent
      property server : String
      property reason : String

      def initialize(@server : String, @reason : String)
      end

      def event_type : String
        "server.disconnected"
      end

      def data : Hash(String, String)
        {"server" => @server, "reason" => @reason}
      end
    end
  end
end