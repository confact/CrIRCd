# Repository for managing users in the IRC network
module Circed
  module Repositories
    class UserRepository
      include Core::Repository(Domain::User)

      @@users = Hash(String, Domain::User).new
      @@clients = Hash(String, Client).new # Maps nickname to local client connection

      def []=(id : String, entity : Domain::User) : Domain::User
        @@users[normalize(id)] = entity
      end

      def []?(id : String) : Domain::User?
        @@users[normalize(id)]?
      end

      def delete(id : String) : Domain::User?
        key = normalize(id)
        removed = @@users.delete(key)
        @@clients.delete(key)
        removed
      end

      def each(& : Domain::User ->) : Nil
        @@users.each_value { |user| yield user }
      end

      def size : Int32
        @@users.size
      end

      def clear : Nil
        @@users.clear
        @@clients.clear
      end

      # Client-specific methods (for local users)
      def add_client(client : Client) : Nil
        if nickname = client.nickname
          @@clients[normalize(nickname)] = client
        end
      end

      def get_client(nickname : String) : Client?
        @@clients[normalize(nickname)]?
      end

      def remove_client(nickname : String) : Bool
        !@@clients.delete(normalize(nickname)).nil?
      end

      def has_client?(nickname : String) : Bool
        @@clients.has_key?(normalize(nickname))
      end

      def each_client(& : Client ->) : Nil
        @@clients.each_value do |client|
          yield client
        end
      end

      def change_nickname(old_nickname : String, new_nickname : String) : Bool
        old_key = normalize(old_nickname)
        new_key = normalize(new_nickname)
        return false unless user = @@users.delete(old_key)

        user.nickname = new_nickname
        @@users[new_key] = user

        if client = @@clients.delete(old_key)
          @@clients[new_key] = client
        end

        true
      end

      private def normalize(nickname : String) : String
        Domain::CaseMapping.normalize(nickname)
      end
    end
  end
end
