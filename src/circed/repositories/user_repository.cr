# Repository for managing users in the IRC network
module Circed
  module Repositories
    class UserRepository
      include Core::Repository(Domain::User)

      @@users = Hash(String, Domain::User).new
      @@clients = Hash(String, Client).new # Maps nickname to local client connection

      def add(nickname : String, user : Domain::User) : Void
        @@users[nickname] = user
      end

      def get(nickname : String) : Domain::User?
        @@users[nickname]?
      end

      def remove(nickname : String) : Bool
        removed = @@users.delete(nickname)
        @@clients.delete(nickname)
        !removed.nil?
      end

      def all : Array(Domain::User)
        @@users.values
      end

      def size : Int32
        @@users.size
      end

      def count : Int32
        @@users.size
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

      def update_nickname(old_nickname : String, new_nickname : String) : Bool
        return false unless @@clients.has_key?(old_nickname)
        
        client = @@clients[old_nickname]
        @@clients.delete(old_nickname)
        @@clients[new_nickname] = client
        
        if user = @@users[old_nickname]?
          @@users.delete(old_nickname)
          user.nickname = new_nickname
          @@users[new_nickname] = user
        end
        
        true
      end

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

      def change_nickname(old_nickname : String, new_nickname : String) : Bool
        if user = @@users[old_nickname]?
          user.nickname = new_nickname
          @@users[new_nickname] = user
          @@users.delete(old_nickname)
          
          if client = @@clients[old_nickname]?
            @@clients[new_nickname] = client
            @@clients.delete(old_nickname)
          end
          
          true
        else
          false
        end
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
        @@users.values.select { |user| user.channels.includes?(channel_name) }
      end

      def local_user_count : Int32
        find_local_users.size
      end

      def remote_user_count : Int32
        find_remote_users.size
      end

      # User state management
      def join_channel(nickname : String, channel_name : String) : Bool
        if user = get(nickname)
          user.channels << channel_name
          true
        else
          false
        end
      end

      def part_channel(nickname : String, channel_name : String) : Bool
        if user = get(nickname)
          user.channels.delete(channel_name)
          true
        else
          false
        end
      end

      def set_away(nickname : String, message : String?) : Bool
        if user = get(nickname)
          user.away_message = message
          true
        else
          false
        end
      end

      def add_mode(nickname : String, mode : Char) : Bool
        if user = get(nickname)
          user.modes << mode
          true
        else
          false
        end
      end

      def remove_mode(nickname : String, mode : Char) : Bool
        if user = get(nickname)
          user.modes.delete(mode)
          true
        else
          false
        end
      end

      def update_activity(nickname : String) : Bool
        if user = get(nickname)
          user.update_activity
          true
        else
          false
        end
      end

      # Statistics
      def statistics : Hash(Symbol, Int32)
        {
          total: size,
          local: local_user_count,
          remote: remote_user_count,
          away: @@users.values.count(&.is_away?)
        }
      end
    end
  end
end