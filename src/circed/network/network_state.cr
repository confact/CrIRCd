module Circed
  module Network
    # Global network state manager for RFC 2813 compliance
    # Maintains network-wide information about servers, users, and channels
    class NetworkState
      # Global server database - all known servers in the network
      @@servers = Hash(String, ServerInfo).new
      
      # Global user database - all users across the network  
      @@users = Hash(String, UserInfo).new
      
      # Global channel database - all channels across the network
      @@channels = Hash(String, ChannelInfo).new
      
      # Network topology - server connections
      @@topology = Hash(String, Set(String)).new

      # Server information structure
      struct ServerInfo
        property name : String
        property hopcount : Int32
        property description : String
        property link_server : LinkServer?
        property token : String?
        property connected_at : Time
        
        def initialize(@name : String, @hopcount : Int32, @description : String, 
                      @link_server : LinkServer? = nil, @token : String? = nil)
          @connected_at = Time.utc
        end
      end

      # User information structure
      struct UserInfo
        property nickname : String
        property username : String
        property hostname : String
        property realname : String
        property server : String
        property hopcount : Int32
        property modes : Set(Char)
        property away_message : String?
        property connected_at : Time
        
        def initialize(@nickname : String, @username : String, @hostname : String,
                      @realname : String, @server : String, @hopcount : Int32 = 0)
          @modes = Set(Char).new
          @connected_at = Time.utc
        end
        
        def hostmask
          "#{nickname}!#{username}@#{hostname}"
        end
      end

      # Channel information structure  
      struct ChannelInfo
        property name : String
        property topic : String?
        property modes : Set(Char)
        property members : Hash(String, Set(Char))  # nickname => user modes in channel
        property created_at : Time
        property topic_set_by : String?
        property topic_set_at : Time?
        
        def initialize(@name : String)
          @modes = Set(Char).new
          @members = Hash(String, Set(Char)).new
          @created_at = Time.utc
        end
      end

      # Add server to global network state
      def self.add_server(name : String, hopcount : Int32, description : String, 
                         link_server : LinkServer? = nil, token : String? = nil)
        server_info = ServerInfo.new(name, hopcount, description, link_server, token)
        @@servers[name] = server_info
        Log.info { "Added server #{name} to network state (hopcount: #{hopcount})" }
      end

      # Remove server and cascade to users/channels
      def self.remove_server(name : String, send_squit : Bool = true)
        return unless @@servers.has_key?(name)
        
        affected_servers = find_affected_servers(name)
        Log.info { "Server #{name} disconnected, affecting #{affected_servers.size} servers total" }
        
        # Collect affected users before removing them
        removed_users = remove_users_from_servers(affected_servers)
        propagate_squits(affected_servers, name) if send_squit
        cleanup_channels(affected_servers)
        update_topology(affected_servers)
        
        # Notify local users about the netsplit with proper user information
        notify_netsplit(name, removed_users)
        
        Log.info { "Cleaned up network state after #{name} disconnect" }
      end

      private def self.notify_netsplit(server_name : String, removed_users : Hash(String, Array(Tuple(String, UserInfo))))
        # Send proper QUIT messages to local users for each removed user
        removed_users.each do |disconnected_server, users|
          users.each do |nickname, user_info|
            send_quit_to_local_users(nickname, user_info, disconnected_server)
          end
        end
      end

      private def self.send_quit_to_local_users(nickname : String, user_info : UserInfo, server_name : String)
        # Find all channels the user was in before being removed
        user_repository = Infrastructure::ServiceLocator.user_repository
        affected_channels = @@channels.select do |_, channel|
          # Check if any local users are in channels (since remote user is already removed)
          channel.members.keys.any? { |nick| user_repository.get_client(nick) }
        end
        
        # Create netsplit quit message
        hostmask = "#{nickname}!#{user_info.username}@#{user_info.hostname}"
        quit_reason = "#{server_name} #{Server.name}"
        quit_message = ":#{hostmask} QUIT :#{quit_reason}"
        
        # Send to all local users (avoid duplicates)
        local_users_notified = Set(String).new
        
        affected_channels.each do |channel_name, channel|
          channel.members.keys.each do |local_nick|
            next if local_users_notified.includes?(local_nick)
            next unless user_repository.get_client(local_nick)
            
            if client = user_repository.get_client(local_nick)
              client.send_message(quit_message)
              local_users_notified << local_nick
            end
          end
        end
      end

      private def self.find_affected_servers(name : String) : Array(String)
        [name] + find_disconnected_servers(name)
      end

      private def self.remove_users_from_servers(server_names : Array(String)) : Hash(String, Array(Tuple(String, UserInfo)))
        removed_users_by_server = Hash(String, Array(Tuple(String, UserInfo))).new
        
        server_names.each do |server_name|
          users_to_remove = @@users.select { |_, user| user.server == server_name }
          removed_users_by_server[server_name] = users_to_remove.to_a
          users_to_remove.each { |nickname, _| remove_user(nickname) }
        end
        
        removed_users_by_server
      end

      private def self.propagate_squits(server_names : Array(String), original_server : String)
        server_names.each do |server_name|
          next if server_name == original_server
          propagate_squit(server_name, "#{original_server} #{server_name}")
        end
      end

      private def self.cleanup_channels(server_names : Array(String))
        @@channels.each do |channel_name, channel|
          server_names.each do |server_name|
            users_on_server = @@users.select { |_, user| user.server == server_name }
            users_on_server.keys.each { |nick| channel.members.delete(nick) }
          end
          
          @@channels.delete(channel_name) if channel.members.empty?
        end
      end

      private def self.update_topology(server_names : Array(String))
        server_names.each do |server_name|
          @@servers.delete(server_name)
          @@topology.delete(server_name)
          @@topology.each { |_, connections| connections.delete(server_name) }
        end
      end

      # Add user to global network state
      def self.add_user(nickname : String, username : String, hostname : String,
                       realname : String, server : String, hopcount : Int32 = 0)
        user_info = UserInfo.new(nickname, username, hostname, realname, server, hopcount)
        @@users[nickname] = user_info
        Log.debug { "Added user #{nickname} to network state on server #{server}" }
      end

      # Remove user from global network state
      def self.remove_user(nickname : String)
        return unless @@users.has_key?(nickname)
        
        # Remove user from all channels
        @@channels.each { |_, channel| channel.members.delete(nickname) }
        
        @@users.delete(nickname)
        Log.debug { "Removed user #{nickname} from network state" }
      end

      # Add channel to global network state
      def self.add_channel(name : String)
        return if @@channels.has_key?(name)
        
        channel_info = ChannelInfo.new(name)
        @@channels[name] = channel_info
        Log.debug { "Added channel #{name} to network state" }
      end

      # Remove channel from global network state
      def self.remove_channel(name : String)
        @@channels.delete(name)
        Log.debug { "Removed channel #{name} from network state" }
      end

      # Join user to channel
      def self.join_user_to_channel(nickname : String, channel_name : String, modes : Set(Char) = Set(Char).new)
        add_channel(channel_name) unless @@channels.has_key?(channel_name)
        
        if channel = @@channels[channel_name]?
          channel.members[nickname] = modes
          Log.debug { "User #{nickname} joined channel #{channel_name} with modes #{modes}" }
        end
      end

      # Part user from channel
      def self.part_user_from_channel(nickname : String, channel_name : String)
        if channel = @@channels[channel_name]?
          channel.members.delete(nickname)
          
          # Remove empty channels
          if channel.members.empty?
            remove_channel(channel_name)
          end
          
          Log.debug { "User #{nickname} parted channel #{channel_name}" }
        end
      end

      # Network topology management
      def self.add_server_link(server1 : String, server2 : String)
        @@topology[server1] ||= Set(String).new
        @@topology[server2] ||= Set(String).new
        @@topology[server1] << server2
        @@topology[server2] << server1
      end

      def self.remove_server_link(server1 : String, server2 : String)
        @@topology[server1]?.try(&.delete(server2))
        @@topology[server2]?.try(&.delete(server1))
      end

      # Query methods
      def self.servers
        @@servers
      end

      def self.users
        @@users
      end

      def self.channels
        @@channels
      end

      def self.topology
        @@topology
      end
      
      # Clear all state (for testing)
      def self.clear_all_state
        @@servers.clear
        @@users.clear
        @@channels.clear
        @@topology.clear
      end

      def self.get_server(name : String)
        @@servers[name]?
      end

      def self.get_user(nickname : String)
        @@users[nickname]?
      end

      def self.get_channel(name : String)
        @@channels[name]?
      end

      # Find all servers that would be disconnected if the given server splits
      private def self.find_disconnected_servers(split_server : String) : Array(String)
        return [] of String unless @@topology.has_key?(split_server)
        
        # Find servers that are only reachable through the split server
        disconnected = [] of String
        
        # Check each server in the topology
        @@servers.keys.each do |server_name|
          next if server_name == Server.name || server_name == split_server
          
          # If this server cannot be reached without going through the split server, it gets disconnected
          unless can_reach_without(server_name, split_server, Server.name, Set(String).new)
            disconnected << server_name
          end
        end
        
        disconnected
      end
      
      # Check if target can be reached from source without going through avoid_server
      private def self.can_reach_without(target : String, avoid_server : String, 
                                        source : String, visited : Set(String)) : Bool
        return true if target == source
        return false if visited.includes?(source) || source == avoid_server
        
        visited << source
        
        # Check all neighbors of source
        if neighbors = @@topology[source]?
          neighbors.each do |neighbor|
            next if neighbor == avoid_server || visited.includes?(neighbor)
            return true if can_reach_without(target, avoid_server, neighbor, visited.dup)
          end
        end
        
        false
      end
      
      # Propagate SQUIT message to all other servers
      private def self.propagate_squit(server_name : String, reason : String)
        ServerHandler.servers.each do |link_server|
          link_server.safe_send("SQUIT #{server_name} :#{reason}")
        end
      end

      # Find route to server (for message routing)
      def self.route_to_server(target_server : String, from_server : String = Server.name) : String?
        return nil if target_server == from_server
        return target_server if @@topology[from_server]?.try(&.includes?(target_server))
        
        # Simple BFS to find route (could be optimized with cached routing tables)
        visited = Set(String).new
        queue = [{from_server, [from_server]}]
        
        while !queue.empty?
          current_server, path = queue.shift
          next if visited.includes?(current_server)
          visited << current_server
          
          if current_server == target_server
            return path.size > 1 ? path[1] : nil
          end
          
          if neighbors = @@topology[current_server]?
            neighbors.each do |neighbor|
              next if visited.includes?(neighbor)
              queue << {neighbor, path + [neighbor]}
            end
          end
        end
        
        nil
      end

      # Generate server list for LINKS command
      def self.server_list(mask : String? = nil)
        servers = @@servers.values
        
        if mask
          # Simple wildcard matching
          pattern = mask.gsub("*", ".*").gsub("?", ".")
          regex = Regex.new("^#{pattern}$", Regex::Options::IGNORE_CASE)
          servers = servers.select { |server| regex.matches?(server.name) }
        end
        
        servers
      end

      # Network statistics
      def self.stats
        {
          servers: @@servers.size,
          users: @@users.size,
          channels: @@channels.size,
          connections: @@topology.sum { |_, connections| connections.size } // 2
        }
      end
    end
  end
end