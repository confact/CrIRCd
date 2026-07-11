# Repository for managing channels in the IRC network
module Circed
  module Repositories
    class ChannelRepository
      include Core::Repository(Domain::Channel)

      @@channels = Hash(String, Domain::Channel).new
      @@user_channels = Hash(String, Set(String)).new

      def []=(id : String, entity : Domain::Channel) : Domain::Channel
        normalized_id = normalize_channel_name(id)
        if existing = @@channels[normalized_id]?
          existing.members.each_key { |nickname| unindex_user_channel(nickname, existing.name) }
        end
        @@channels[normalized_id] = entity
        index_channel_members(entity.name, entity)
        entity
      end

      def []?(id : String) : Domain::Channel?
        @@channels[normalize_channel_name(id)]?
      end

      def delete(id : String) : Domain::Channel?
        normalized_id = normalize_channel_name(id)
        if channel = @@channels.delete(normalized_id)
          channel.members.each_key { |nickname| unindex_user_channel(nickname, channel.name) }
          channel
        end
      end

      def each(& : Domain::Channel ->) : Nil
        @@channels.each_value { |channel| yield channel }
      end

      def size : Int32
        @@channels.size
      end

      def clear : Nil
        @@channels.clear
        @@user_channels.clear
      end

      # Channel-specific operations
      def create_channel(name : String) : Domain::Channel
        normalized_name = normalize_channel_name(name)
        @@channels.put_if_absent(normalized_name) { Domain::Channel.new(channel_name(name)) }
      end

      def add_member(channel_name : String, nickname : String, modes : Set(Char) = Set(Char).new) : Nil
        channel = create_channel(channel_name)
        channel.add_member(nickname, modes)
        index_user_channel(nickname, channel.name)
      end

      def part_user(channel_name : String, nickname : String) : Bool
        return false unless channel = self[channel_name]?

        removed = channel.remove_member(nickname)
        unindex_user_channel(nickname, channel.name) if removed
        delete(channel.name) if channel.empty?
        removed
      end

      # Query methods
      def each_user_channel(nickname : String, & : Domain::Channel ->) : Nil
        return unless channel_names = @@user_channels[normalize_nickname(nickname)]?

        channel_names.each do |channel_name|
          if channel = self[channel_name]?
            yield channel
          end
        end
      end

      def find_user_channels(nickname : String) : Array(Domain::Channel)
        capacity = @@user_channels[normalize_nickname(nickname)]?.try(&.size) || 0
        channels = Array(Domain::Channel).new(capacity)
        each_user_channel(nickname) { |channel| channels << channel }
        channels
      end

      def find_user_channel_names(nickname : String) : Array(String)
        @@user_channels[normalize_nickname(nickname)]?.try(&.to_a) || [] of String
      end

      def user_in_channel?(channel_name : String, nickname : String) : Bool
        self[channel_name]?.try(&.has_member?(nickname)) || false
      end

      # Bulk operations
      def remove_user_from_all_channels(nickname : String) : Set(String)
        channel_names = @@user_channels.delete(normalize_nickname(nickname))
        return Set(String).new unless channel_names

        channel_names.each do |channel_name|
          next unless channel = self[channel_name]?
          next unless channel.remove_member(nickname)

          delete(channel_name) if channel.empty?
        end

        channel_names
      end

      def rename_member(old_nickname : String, new_nickname : String) : Set(String)
        channel_names = @@user_channels.delete(normalize_nickname(old_nickname))
        return Set(String).new unless channel_names

        channel_names.each do |channel_name|
          next unless channel = self[channel_name]?
          next unless channel.rename_member(old_nickname, new_nickname)

          index_user_channel(new_nickname, channel_name)
        end

        channel_names
      end

      private def normalize_channel_name(name : String) : String
        Domain::CaseMapping.normalize(channel_name(name))
      end

      private def channel_name(name : String) : String
        "#&+!".includes?(name[0]) ? name : "##{name}"
      end

      private def normalize_nickname(nickname : String) : String
        Domain::CaseMapping.normalize(nickname)
      end

      private def index_channel_members(channel_name : String, channel : Domain::Channel) : Nil
        channel.members.each_key { |nickname| index_user_channel(nickname, channel_name) }
      end

      private def index_user_channel(nickname : String, channel_name : String) : Nil
        @@user_channels.put_if_absent(normalize_nickname(nickname)) { Set(String).new } << channel_name
      end

      private def unindex_user_channel(nickname : String, channel_name : String) : Nil
        normalized_nickname = normalize_nickname(nickname)
        return unless channels = @@user_channels[normalized_nickname]?

        channels.delete(channel_name)
        @@user_channels.delete(normalized_nickname) if channels.empty?
      end
    end
  end
end
