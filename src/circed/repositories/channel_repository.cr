# Repository for managing channels in the IRC network
module Circed
  module Repositories
    class ChannelRepository
      include Core::Repository(Domain::Channel)

      @@channels = Hash(String, Domain::Channel).new
      @@user_channels = Hash(String, Set(String)).new

      def add(id : String, entity : Domain::Channel) : Void
        normalized_id = normalize_channel_name(id)
        @@channels[normalized_id] = entity
        index_channel_members(normalized_id, entity)
      end

      def get(id : String) : Domain::Channel?
        @@channels[normalize_channel_name(id)]?
      end

      def remove(id : String) : Bool
        normalized_id = normalize_channel_name(id)
        if channel = @@channels.delete(normalized_id)
          channel.members.each_key { |nickname| unindex_user_channel(nickname, normalized_id) }
          true
        else
          false
        end
      end

      def all : Array(Domain::Channel)
        @@channels.values
      end

      def size : Int32
        @@channels.size
      end

      def count : Int32
        size
      end

      def exists?(name : String) : Bool
        @@channels.has_key?(normalize_channel_name(name))
      end

      # Unified join method that handles both password and modes
      def join_user(channel_name : String, nickname : String, password : String? = nil, modes : Set(Char) = Set(Char).new) : Bool
        channel = create_channel(channel_name)

        # Password validation if provided
        if password
          return false unless channel.password_matches?(password)
        end

        add_member(channel.name, nickname, modes)
      end

      def clear : Void
        @@channels.clear
        @@user_channels.clear
      end

      # Channel-specific operations
      def create_channel(name : String) : Domain::Channel
        normalized_name = normalize_channel_name(name)

        if existing = @@channels[normalized_name]?
          return existing
        end

        channel = Domain::Channel.new(normalized_name)
        add(normalized_name, channel)
        channel
      end

      def add_member(channel_name : String, nickname : String, modes : Set(Char) = Set(Char).new) : Bool
        channel = create_channel(channel_name)
        channel.add_member(nickname, modes)
        index_user_channel(nickname, channel.name)
        true
      end

      def part_user(channel_name : String, nickname : String) : Bool
        normalized_name = normalize_channel_name(channel_name)
        if channel = get(normalized_name)
          removed = channel.remove_member(nickname)
          unindex_user_channel(nickname, normalized_name) if removed

          # Remove empty channels
          if channel.empty?
            remove(normalized_name)
          end

          removed
        else
          false
        end
      end

      def set_topic(channel_name : String, topic : String, set_by : String) : Bool
        if channel = get(channel_name)
          channel.topic = topic
          channel.topic_set_by = set_by
          channel.topic_set_at = Time.utc
          true
        else
          false
        end
      end

      def add_channel_mode(channel_name : String, mode : Char) : Bool
        if channel = get(channel_name)
          channel.modes << mode
          true
        else
          false
        end
      end

      def remove_channel_mode(channel_name : String, mode : Char) : Bool
        if channel = get(channel_name)
          channel.modes.delete(mode)
          true
        else
          false
        end
      end

      def set_user_mode(channel_name : String, nickname : String, mode : Char, add : Bool) : Bool
        return false unless user_modes = get_user_modes_in_channel(channel_name, nickname)

        add ? user_modes << mode : user_modes.delete(mode)
        true
      end

      # Query methods
      def find_user_channels(nickname : String) : Array(Domain::Channel)
        channel_names = @@user_channels[nickname]?
        return [] of Domain::Channel unless channel_names

        channels = Array(Domain::Channel).new(channel_names.size)
        channel_names.each do |channel_name|
          if channel = @@channels[channel_name]?
            channels << channel
          end
        end
        channels
      end

      def find_user_channel_names(nickname : String) : Array(String)
        @@user_channels[nickname]?.try(&.to_a) || [] of String
      end

      def find_channels_with_local_users(user_repository : UserRepository) : Array(Domain::Channel)
        @@channels.values.select do |channel|
          channel.members.keys.any? { |nick| user_repository.has_client?(nick) }
        end
      end

      def get_channel_users(channel_name : String) : Array(String)
        get(channel_name).try(&.members.keys) || Array(String).new
      end

      def user_in_channel?(channel_name : String, nickname : String) : Bool
        get(channel_name).try(&.has_member?(nickname)) || false
      end

      def get_user_modes_in_channel(channel_name : String, nickname : String) : Set(Char)?
        get(channel_name).try(&.members[nickname]?)
      end

      def user_operator?(channel_name : String, nickname : String) : Bool
        get_user_modes_in_channel(channel_name, nickname).try(&.includes?('o')) || false
      end

      def user_voiced?(channel_name : String, nickname : String) : Bool
        get_user_modes_in_channel(channel_name, nickname).try(&.includes?('v')) || false
      end

      # Bulk operations
      def remove_user_from_all_channels(nickname : String) : Array(String)
        channel_names = @@user_channels.delete(nickname)
        return [] of String unless channel_names

        affected_channels = Array(String).new(channel_names.size)

        channel_names.each do |channel_name|
          next unless channel = @@channels[channel_name]?
          next unless channel.remove_member(nickname)

          affected_channels << channel_name
          remove(channel_name) if channel.empty?
        end

        affected_channels
      end

      def rename_member(old_nickname : String, new_nickname : String) : Array(String)
        channel_names = @@user_channels.delete(old_nickname)
        return [] of String unless channel_names

        renamed_channels = Array(String).new(channel_names.size)
        channel_names.each do |channel_name|
          next unless channel = @@channels[channel_name]?
          next unless modes = channel.members.delete(old_nickname)

          channel.members[new_nickname] = modes
          index_user_channel(new_nickname, channel_name)
          renamed_channels << channel_name
        end

        renamed_channels
      end

      def cleanup_empty_channels : Int32
        removed_count = 0

        @@channels.select { |_, channel| channel.empty? }.each do |name, _|
          remove(name)
          removed_count += 1
        end

        removed_count
      end

      # Statistics
      def statistics : Hash(Symbol, Int32)
        total_members = @@channels.values.sum(&.member_count)

        {
          total:           size,
          total_members:   total_members,
          average_members: size > 0 ? (total_members / size) : 0,
          empty:           @@channels.values.count(&.empty?),
        }
      end

      private def normalize_channel_name(name : String) : String
        # Ensure channel name starts with # if it doesn't already
        name.starts_with?('#') || name.starts_with?('&') ? name : "##{name}"
      end

      private def index_channel_members(channel_name : String, channel : Domain::Channel) : Void
        channel.members.each_key { |nickname| index_user_channel(nickname, channel_name) }
      end

      private def index_user_channel(nickname : String, channel_name : String) : Void
        channels = @@user_channels[nickname] ||= Set(String).new
        channels << channel_name
      end

      private def unindex_user_channel(nickname : String, channel_name : String) : Void
        return unless channels = @@user_channels[nickname]?

        channels.delete(channel_name)
        @@user_channels.delete(nickname) if channels.empty?
      end
    end
  end
end
