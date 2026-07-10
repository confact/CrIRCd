require "deque"

module Circed
  module Network
    # Global network state manager for RFC 2813 compliance
    # Maintains network-wide information about servers, users, and channels
    class NetworkState
      # Global server database - all known servers in the network
      # Pre-allocate capacity for better performance
      @@servers = Hash(String, ServerInfo).new(initial_capacity: 64)

      # Global user database - all users across the network
      @@users = Hash(String, UserInfo).new(initial_capacity: 1024)

      # Global channel database - all channels across the network
      @@channels = Hash(String, ChannelInfo).new(initial_capacity: 256)

      # Network topology - server connections
      @@topology = Hash(String, Set(String)).new(initial_capacity: 64)

      NICKNAME_DELAY = 30.seconds
      @@recent_nicknames = Hash(String, Time).new

      # Server information structure - using struct for performance
      struct ServerInfo
        getter name : String
        getter hopcount : Int32
        getter description : String
        getter link_server : LinkServer?
        getter token : String?
        getter connected_at : Time

        def initialize(@name : String, @hopcount : Int32, @description : String,
                       @link_server : LinkServer? = nil, @token : String? = nil)
          @connected_at = Time.utc
        end
      end

      # User information structure - using struct for performance
      struct UserInfo
        getter nickname : String
        getter username : String
        getter hostname : String
        getter realname : String
        getter server : String
        getter hopcount : Int32
        property modes : Set(Char)      # Mutable for mode changes
        property away_message : String? # Mutable for away status
        getter connected_at : Time
        @hostmask : String? # Cached hostmask

        def initialize(@nickname : String, @username : String, @hostname : String,
                       @realname : String, @server : String, @hopcount : Int32 = 0,
                       @connected_at : Time = Time.unix(Time.utc.to_unix))
          @modes = Set(Char).new(initial_capacity: 4) # Most users have few modes
          @hostmask = nil
        end

        # Cached hostmask generation for better performance
        def hostmask : String
          @hostmask ||= String.build(capacity: @nickname.size + @username.size + @hostname.size + 2) do |io|
            io << @nickname << '!' << @username << '@' << @hostname
          end
        end
      end

      # Channel information structure - using struct for performance
      struct ChannelInfo
        getter name : String
        property topic : String?                   # Mutable for topic changes
        property modes : Set(Char)                 # Mutable for mode changes
        property members : Hash(String, Set(Char)) # Mutable for joins/parts
        property created_at : Time
        property topic_set_by : String? # Mutable for topic updates
        property topic_set_at : Time?   # Mutable for topic updates
        property password : String?
        property user_limit : Int32?
        property ban_list : Set(String)
        @member_names : Hash(String, String)

        def initialize(@name : String, @created_at : Time = Time.unix(Time.utc.to_unix))
          @modes = Set(Char).new
          @members = Hash(String, Set(Char)).new
          @member_names = Hash(String, String).new
          @ban_list = Set(String).new
        end

        def has_member?(nickname : String) : Bool
          @member_names.has_key?(Domain::CaseMapping.normalize(nickname))
        end

        def add_member(nickname : String, modes : Set(Char)) : Nil
          key = Domain::CaseMapping.normalize(nickname)
          if display_name = @member_names[key]?
            @members[display_name] = modes
          else
            @member_names[key] = nickname
            @members[nickname] = modes
          end
        end

        def remove_member(nickname : String) : Set(Char)?
          return unless display_name = @member_names.delete(Domain::CaseMapping.normalize(nickname))

          @members.delete(display_name)
        end

        def rename_member(old_nickname : String, new_nickname : String) : Bool
          return false unless modes = remove_member(old_nickname)

          add_member(new_nickname, modes)
          true
        end

        def replace_members(members : Hash(String, Set(Char))) : Nil
          @members.clear
          @member_names.clear
          members.each { |nickname, modes| add_member(nickname, modes.dup) }
        end
      end

      # Add server to global network state
      def self.add_server(name : String, hopcount : Int32, description : String,
                          link_server : LinkServer? = nil, token : String? = nil) : Bool
        return false if name == Server.name || @@servers.has_key?(name)

        server_info = ServerInfo.new(name, hopcount, description, link_server, token)
        @@servers[name] = server_info
        Log.info { "Added server #{name} to network state (hopcount: #{hopcount})" }
        true
      end

      # Remove server and cascade to users/channels
      def self.remove_server(name : String, send_squit : Bool = true)
        return unless @@servers.has_key?(name)

        affected_servers = find_affected_servers(name)
        Log.info { "Server #{name} disconnected, affecting #{affected_servers.size} servers total" }

        # Collect affected users before removing them
        removed_users = remove_users_from_servers(affected_servers)
        propagate_squits(affected_servers, name) if send_squit
        cleanup_empty_channels
        update_topology(affected_servers)

        # Notify local users about the netsplit with proper user information
        notify_netsplit(removed_users)

        Log.info { "Cleaned up network state after #{name} disconnect" }
      end

      private def self.notify_netsplit(removed_users : Hash(String, Array(Tuple(String, UserInfo, Set(String)))))
        # Send proper QUIT messages to local users for each removed user
        removed_users.each do |disconnected_server, users|
          users.each do |(_, user_info, recipients)|
            send_quit_to_local_users(user_info, disconnected_server, recipients)
          end
        end
      end

      private def self.send_quit_to_local_users(user_info : UserInfo, server_name : String, recipients : Set(String))
        user_repository = Infrastructure::ServiceLocator.user_repository

        # Build quit message once with optimal capacity
        hostmask = user_info.hostmask
        quit_message_capacity = hostmask.size + server_name.size + Server.name.size + 10
        quit_message = String.build(capacity: quit_message_capacity) do |io|
          io << ':' << hostmask << " QUIT :" << Server.name << ' ' << server_name
        end

        recipients.each do |nickname|
          user_repository.get_client(nickname).try(&.send_message(quit_message))
        end
      end

      private def self.find_affected_servers(name : String) : Set(String)
        affected_servers = Set{name}
        return affected_servers unless @@topology.has_key?(name)

        @@servers.each_key do |server_name|
          next if server_name == Server.name || server_name == name

          affected_servers << server_name unless can_reach_without(server_name, name, Server.name)
        end

        affected_servers
      end

      private def self.remove_users_from_servers(server_names : Set(String)) : Hash(String, Array(Tuple(String, UserInfo, Set(String))))
        removed_users_by_server = Hash(String, Array(Tuple(String, UserInfo, Set(String)))).new

        @@users.each do |nickname, user|
          next unless server_names.includes?(user.server)

          users = removed_users_by_server.put_if_absent(user.server) { [] of Tuple(String, UserInfo, Set(String)) }
          users << {nickname, user, local_channel_peers(nickname)}
        end

        removed_users_by_server.each_value do |users|
          users.each do |(nickname, _, _)|
            Infrastructure::ServiceLocator.channel_repository.remove_user_from_all_channels(nickname)
            remove_user(nickname)
          end
        end

        removed_users_by_server
      end

      private def self.local_channel_peers(nickname : String) : Set(String)
        user_repository = Infrastructure::ServiceLocator.user_repository
        recipients = Set(String).new

        @@channels.each_value do |channel|
          next unless channel.has_member?(nickname)

          channel.members.each_key do |member|
            recipients << member if user_repository.has_client?(member)
          end
        end

        recipients
      end

      private def self.propagate_squits(server_names : Set(String), original_server : String)
        server_names.each do |server_name|
          next if server_name == original_server
          propagate_squit(server_name, "#{original_server} #{server_name}")
        end
      end

      private def self.cleanup_empty_channels
        @@channels.reject! { |_, channel| channel.members.empty? }
      end

      private def self.update_topology(server_names : Set(String))
        server_names.each do |server_name|
          @@servers.delete(server_name)
          @@topology.delete(server_name)
          @@topology.each { |_, connections| connections.delete(server_name) }
        end
      end

      # Add user to global network state
      def self.add_user(nickname : String, username : String, hostname : String,
                        realname : String, server : String, hopcount : Int32 = 0,
                        connected_at : Time = Time.unix(Time.utc.to_unix)) : Bool
        key = user_key(nickname)
        if existing = @@users[key]?
          return false unless connected_at < existing.connected_at ||
                              connected_at == existing.connected_at && server < existing.server

          Infrastructure::ServiceLocator.channel_repository.remove_user_from_all_channels(nickname)
          if client = Infrastructure::ServiceLocator.user_repository.get_client(nickname)
            client.send_error("Nickname collision")
            client.shutdown
          end
          remove_user(nickname)
        end

        user_info = UserInfo.new(nickname, username, hostname, realname, server, hopcount, connected_at)
        @@users[key] = user_info
        @@recent_nicknames.delete(key)
        Log.debug { "Added user #{nickname} to network state on server #{server}" }
        true
      end

      # Remove user from global network state - optimized
      def self.remove_user(nickname : String)
        key = user_key(nickname)
        return unless @@users.delete(key)

        @@recent_nicknames[key] = Time.utc + NICKNAME_DELAY

        # Remove user from all channels efficiently
        @@channels.each_value(&.remove_member(nickname))

        Log.debug { "Removed user #{nickname} from network state" }
      end

      # Add channel to global network state
      def self.add_channel(name : String, created_at : Time = Time.unix(Time.utc.to_unix))
        key = channel_key(name)
        return if @@channels.has_key?(key)

        channel_info = ChannelInfo.new(name, created_at)
        @@channels[key] = channel_info
        Log.debug { "Added channel #{name} to network state" }
      end

      def self.merge_channel(name : String, created_at : Time, modes : Set(Char)) : Bool
        key = channel_key(name)
        unless channel = @@channels[key]?
          channel = ChannelInfo.new(name, created_at)
          channel.modes = modes.dup
          @@channels[key] = channel
          return true
        end

        if created_at < channel.created_at
          channel.created_at = created_at
          channel.modes = modes.dup
          channel.topic = nil
          channel.topic_set_by = nil
          channel.topic_set_at = nil
          channel.password = nil
          channel.user_limit = nil
          channel.ban_list.clear
          channel.members.each_value(&.clear)
          @@channels[key] = channel
          return true
        end

        return false if created_at > channel.created_at

        channel.modes.concat(modes)
        true
      end

      def self.sync_channel_repository(name : String) : Nil
        return unless channel = @@channels[channel_key(name)]?

        repository = Infrastructure::ServiceLocator.channel_repository
        repository_channel = repository.create_channel(name)
        repository_channel.created_at = channel.created_at
        repository_channel.modes = channel.modes.dup
        repository_channel.topic = channel.topic
        repository_channel.topic_set_by = channel.topic_set_by
        repository_channel.topic_set_at = channel.topic_set_at
        repository_channel.password = channel.password
        repository_channel.user_limit = channel.user_limit
        repository_channel.ban_list = channel.ban_list.dup
        channel.members.each do |nickname, modes|
          repository.add_member(name, nickname, modes.dup)
        end
      end

      def self.sync_channel(channel : Domain::Channel) : Nil
        key = channel_key(channel.name)
        network_channel = @@channels[key]? || ChannelInfo.new(channel.name, channel.created_at)
        network_channel.created_at = channel.created_at
        network_channel.modes = channel.modes.dup
        network_channel.topic = channel.topic
        network_channel.topic_set_by = channel.topic_set_by
        network_channel.topic_set_at = channel.topic_set_at
        network_channel.password = channel.password
        network_channel.user_limit = channel.user_limit
        network_channel.ban_list = channel.ban_list.dup
        network_channel.replace_members(channel.members)
        @@channels[key] = network_channel
      end

      def self.apply_channel_modes(name : String, mode_string : String, params : Array(String),
                                   created_at : Time? = nil, parameter_index : Int32 = 0) : Bool
        return false unless channel = @@channels[channel_key(name)]?
        return false if created_at && created_at != channel.created_at

        sync_channel_repository(name)
        return false unless repository_channel = Infrastructure::ServiceLocator.channel_repository[name]?

        repository_channel.apply_modes(mode_string, params, parameter_index)
        sync_channel(repository_channel)
        true
      end

      def self.nickname_reserved?(nickname : String) : Bool
        key = user_key(nickname)
        return false unless expires_at = @@recent_nicknames[key]?
        return true if expires_at > Time.utc

        @@recent_nicknames.delete(key)
        false
      end

      # Remove channel from global network state
      def self.remove_channel(name : String)
        @@channels.delete(channel_key(name))
        Log.debug { "Removed channel #{name} from network state" }
      end

      # Join user to channel
      def self.join_user_to_channel(nickname : String, channel_name : String, modes : Set(Char) = Set(Char).new)
        key = channel_key(channel_name)
        add_channel(channel_name) unless @@channels.has_key?(key)

        if channel = @@channels[key]?
          channel.add_member(nickname, modes)
          Log.debug { "User #{nickname} joined channel #{channel_name} with modes #{modes}" }
        end
      end

      # Part user from channel
      def self.part_user_from_channel(nickname : String, channel_name : String)
        if channel = @@channels[channel_key(channel_name)]?
          channel.remove_member(nickname)

          # Remove empty channels
          if channel.members.empty?
            remove_channel(channel_name)
          end

          Log.debug { "User #{nickname} parted channel #{channel_name}" }
        end
      end

      # Network topology management
      def self.add_server_link(server1 : String, server2 : String) : Bool
        return false if server1 == server2
        return true if @@topology[server1]?.try(&.includes?(server2))
        return false if route_to_server(server2, server1)

        @@topology.put_if_absent(server1) { Set(String).new } << server2
        @@topology.put_if_absent(server2) { Set(String).new } << server1
        true
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
        @@recent_nicknames.clear
      end

      def self.get_server(name : String)
        @@servers[name]?
      end

      def self.get_user(nickname : String)
        @@users[user_key(nickname)]?
      end

      def self.user_routed_through?(nickname : String, server_name : String) : Bool
        return false unless user = @@users[user_key(nickname)]?

        user.server == server_name || route_to_server(user.server) == server_name
      end

      # Set away message for a user - optimized
      def self.set_user_away(nickname : String, message : String?)
        key = user_key(nickname)
        return unless user = @@users[key]?

        user.away_message = message
        @@users[key] = user
      end

      def self.get_channel(name : String)
        @@channels[channel_key(name)]?
      end

      # Set topic for a channel
      def self.set_channel_topic(name : String, topic : String?, set_by : String? = nil,
                                 set_at : Time = Time.unix(Time.utc.to_unix), created_at : Time? = nil) : Bool
        key = channel_key(name)
        return false unless channel = @@channels[key]?
        return false if created_at && created_at != channel.created_at
        return false if channel.topic_set_at.try { |current| set_at < current }

        channel.topic = topic
        channel.topic_set_by = set_by
        channel.topic_set_at = topic ? set_at : nil
        @@channels[key] = channel
        true
      end

      private def self.user_key(nickname : String) : String
        Domain::CaseMapping.normalize(nickname)
      end

      private def self.channel_key(name : String) : String
        Domain::CaseMapping.normalize(name)
      end

      # Check if target can be reached from source without going through avoid_server
      private def self.can_reach_without(target : String, avoid_server : String,
                                         source : String, visited : Set(String) = Set(String).new) : Bool
        return true if target == source
        return false if source == avoid_server || !visited.add?(source)
        return false unless neighbors = @@topology[source]?

        neighbors.any? { |neighbor| can_reach_without(target, avoid_server, neighbor, visited) }
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

        visited = Set{from_server}
        queue = Deque({String, String}).new

        if neighbors = @@topology[from_server]?
          neighbors.each do |neighbor|
            queue << {neighbor, neighbor} if visited.add?(neighbor)
          end
        end

        while route = queue.shift?
          server, first_hop = route
          return first_hop if server == target_server

          if neighbors = @@topology[server]?
            neighbors.each do |neighbor|
              queue << {neighbor, first_hop} if visited.add?(neighbor)
            end
          end
        end

        nil
      end

      # Generate server list for LINKS command
      def self.server_list(mask : String? = nil)
        servers = @@servers.each_value
        return servers unless mask

        servers.select { |server| Domain::Wildcard.match?(mask, server.name) }
      end

      # Network statistics
      def self.stats
        {
          servers:     @@servers.size,
          users:       @@users.size,
          channels:    @@channels.size,
          connections: @@topology.sum { |_, connections| connections.size } // 2,
        }
      end
    end
  end
end
