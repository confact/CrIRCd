# Repository for managing users in the IRC network
module Circed
  module Repositories
    class UserRepository
      include Core::Repository(Domain::User)

      @@users = Hash(String, Domain::User).new
      @@clients = Hash(String, Client).new # Maps nickname to local client connection

      def add(id : String, entity : Domain::User) : Void
        @@users[id] = entity
      end

      def get(id : String) : Domain::User?
        @@users[id]?
      end

      def remove(id : String) : Bool
        removed = @@users.delete(id)
        @@clients.delete(id)
        !removed.nil?
      end

      def all : Array(Domain::User)
        @@users.values
      end

      def size : Int32
        @@users.size
      end

      def count : Int32
        size
      end

      def add_user(user : User) : Void
        # Legacy User class support - convert to Domain::User if needed
        domain_user = Domain::User.new(
          user.nickname,
          user.username,
          user.hostname,
          user.realname,
          user.servername,
          user.hopcount
        )
        @@users[user.nickname] = domain_user
      end

      # Removed duplicate - use change_nickname instead

      def clear : Void
        @@users.clear
        @@clients.clear
      end

      # Client-specific methods (for local users)
      def add_client(client : Client) : Void
        if nickname = client.nickname
          @@clients[nickname] = client
        end
      end

      def get_client(nickname : String) : Client?
        @@clients[nickname]?
      end

      def remove_client(nickname : String) : Bool
        !@@clients.delete(nickname).nil?
      end

      def has_client?(nickname : String) : Bool
        @@clients.has_key?(nickname)
      end

      def each_client(& : Client ->) : Nil
        @@clients.each_value do |client|
          yield client
        end
      end

      def change_nickname(old_nickname : String, new_nickname : String) : Bool
        user = @@users[old_nickname]?
        return false unless user

        # Update user
        user.nickname = new_nickname
        @@users[new_nickname] = user
        @@users.delete(old_nickname)

        # Update client if exists
        if client = @@clients[old_nickname]?
          @@clients[new_nickname] = client
          @@clients.delete(old_nickname)
        end

        true
      end

      def update_nickname(old_nickname : String, new_nickname : String) : Bool
        change_nickname(old_nickname, new_nickname)
      end

      # Query methods
      def find_by_server(server_name : String) : Array(Domain::User)
        @@users.values.select { |user| user.server == server_name }
      end

      def find_local_users : Array(Domain::User)
        @@users.values.select(&.is_local?)
      end

      def find_remote_users : Array(Domain::User)
        @@users.values.reject(&.is_local?)
      end

      def find_users_in_channel(channel_name : String) : Array(Domain::User)
        @@users.values.select(&.channels.includes?(channel_name))
      end

      def local_user_count : Int32
        find_local_users.size
      end

      def remote_user_count : Int32
        find_remote_users.size
      end

      # User state management
      def join_channel(nickname : String, channel_name : String) : Bool
        update_user(nickname) do |user|
          user.channels << channel_name
        end
      end

      def part_channel(nickname : String, channel_name : String) : Bool
        update_user(nickname) do |user|
          user.channels.delete(channel_name)
        end
      end

      def set_away(nickname : String, message : String?) : Bool
        update_user(nickname) do |user|
          user.away_message = message
        end
      end

      def add_mode(nickname : String, mode : Char) : Bool
        update_user(nickname) do |user|
          user.modes << mode
        end
      end

      def remove_mode(nickname : String, mode : Char) : Bool
        update_user(nickname) do |user|
          user.modes.delete(mode)
        end
      end

      def update_activity(nickname : String) : Bool
        update_user(nickname) do |user|
          user.update_activity
        end
      end

      # Statistics
      def statistics : Hash(Symbol, Int32)
        {
          total:  size,
          local:  local_user_count,
          remote: remote_user_count,
          away:   @@users.values.count(&.is_away?),
        }
      end

      private def update_user(nickname : String, & : Domain::User ->) : Bool
        return false unless user = get(nickname)

        yield user
        true
      end
    end
  end
end
