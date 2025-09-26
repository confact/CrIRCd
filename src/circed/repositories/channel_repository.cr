# Repository for managing channels in the IRC network
module Circed
  module Repositories
    class ChannelRepository
      include Core::Repository(Domain::Channel)

      @@channels = Hash(String, Domain::Channel).new

      def add(name : String, channel : Domain::Channel) : Void
        @@channels[name] = channel
      end

      def get(name : String) : Domain::Channel?
        @@channels[name]?
      end

      def remove(name : String) : Bool
        !@@channels.delete(name).nil?
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
        @@channels.has_key?(name)
      end

      # Unified join method that handles both password and modes
      def join_user(channel_name : String, nickname : String, password : String? = nil, modes : Set(Char) = Set(Char).new) : Bool
        channel = create_channel(channel_name)

        # Password validation if provided
        if password
          return false unless channel.password_matches?(password)
        end

        channel.add_member(nickname, modes)
        true
      end

      def clear : Void
        @@channels.clear
      end

      # Channel-specific operations
      def create_channel(name : String) : Domain::Channel
        normalized_name = normalize_channel_name(name)

        if existing = get(normalized_name)
          existing
        else
          channel = Domain::Channel.new(normalized_name)
          add(normalized_name, channel)
          channel
        end
      end

      def part_user(channel_name : String, nickname : String) : Bool
        if channel = get(channel_name)
          removed = channel.remove_member(nickname)

          # Remove empty channels
          if channel.empty?
            remove(channel_name)
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
        if channel = get(channel_name)
          if channel.has_member?(nickname)
            user_modes = channel.members[nickname]
            if add
              user_modes << mode
            else
              user_modes.delete(mode)
            end
            true
          else
            false
          end
        else
          false
        end
      end

      # Query methods
      def find_user_channels(nickname : String) : Array(Domain::Channel)
        @@channels.values.select { |channel| channel.has_member?(nickname) }
      end

      def find_channels_with_local_users(user_repository : UserRepository) : Array(Domain::Channel)
        @@channels.values.select do |channel|
          channel.members.keys.any? { |nick| user_repository.has_client?(nick) }
        end
      end

      def get_channel_users(channel_name : String) : Array(String)
        if channel = get(channel_name)
          channel.members.keys
        else
          Array(String).new
        end
      end

      def is_user_in_channel?(channel_name : String, nickname : String) : Bool
        get(channel_name).try(&.has_member?(nickname)) || false
      end

      def get_user_modes_in_channel(channel_name : String, nickname : String) : Set(Char)?
        if channel = get(channel_name)
          channel.members[nickname]?
        else
          nil
        end
      end

      def is_user_operator?(channel_name : String, nickname : String) : Bool
        get_user_modes_in_channel(channel_name, nickname).try(&.includes?('o')) || false
      end

      def is_user_voiced?(channel_name : String, nickname : String) : Bool
        get_user_modes_in_channel(channel_name, nickname).try(&.includes?('v')) || false
      end

      # Bulk operations
      def remove_user_from_all_channels(nickname : String) : Array(String)
        affected_channels = Array(String).new

        @@channels.each do |channel_name, channel|
          if channel.remove_member(nickname)
            affected_channels << channel_name

            # Remove empty channels
            if channel.empty?
              remove(channel_name)
            end
          end
        end

        affected_channels
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
    end
  end
end
