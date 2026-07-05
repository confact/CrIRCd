# Repository for managing servers in the IRC network
module Circed
  module Repositories
    class ServerRepository
      include Core::Repository(Domain::Server)

      @@servers = Hash(String, Domain::Server).new
      @@topology = Hash(String, Set(String)).new # server -> connected servers

      def add(id : String, entity : Domain::Server) : Void
        @@servers[id] = entity
        @@topology[id] ||= Set(String).new
      end

      def get(id : String) : Domain::Server?
        @@servers[id]?
      end

      def remove(id : String) : Bool
        removed_server = @@servers.delete(id)
        @@topology.delete(id)

        # Remove from other servers' topology
        @@topology.each do |_, connections|
          connections.delete(id)
        end

        !removed_server.nil?
      end

      def all : Array(Domain::Server)
        @@servers.values
      end

      def size : Int32
        @@servers.size
      end

      def clear : Void
        @@servers.clear
        @@topology.clear
      end

      # Topology management
      def add_link(server1 : String, server2 : String) : Void
        @@topology[server1] ||= Set(String).new
        @@topology[server2] ||= Set(String).new
        @@topology[server1] << server2
        @@topology[server2] << server1
      end

      def remove_link(server1 : String, server2 : String) : Void
        @@topology[server1]?.try(&.delete(server2))
        @@topology[server2]?.try(&.delete(server1))
      end

      def get_connections(server_name : String) : Set(String)
        @@topology[server_name]? || Set(String).new
      end

      def are_connected?(server1 : String, server2 : String) : Bool
        @@topology[server1]?.try(&.includes?(server2)) || false
      end

      # Network topology analysis
      def find_route_to_server(target : String, from : String = "localhost") : String?
        return nil if target == from
        return target if are_connected?(from, target)

        # BFS to find route
        visited = Set(String).new
        queue = [{from, [from]}]

        while !queue.empty?
          current_server, path = queue.shift
          next if visited.includes?(current_server)
          visited << current_server

          if current_server == target
            return path.size > 1 ? path[1] : nil
          end

          if connections = @@topology[current_server]?
            connections.each do |neighbor|
              next if visited.includes?(neighbor)
              queue << {neighbor, path + [neighbor]}
            end
          end
        end

        nil
      end

      def find_servers_behind(split_server : String, from : String = "localhost") : Array(String)
        return [] of String unless @@topology.has_key?(split_server)

        disconnected = [] of String

        @@servers.each_key do |server_name|
          next if server_name == from || server_name == split_server

          unless can_reach_without(server_name, split_server, from, Set(String).new)
            disconnected << server_name
          end
        end

        disconnected
      end

      private def can_reach_without(target : String, avoid : String, source : String, visited : Set(String)) : Bool
        return true if target == source
        return false if visited.includes?(source) || source == avoid

        visited << source

        if connections = @@topology[source]?
          connections.each do |neighbor|
            next if neighbor == avoid || visited.includes?(neighbor)
            return true if can_reach_without(target, avoid, neighbor, visited.dup)
          end
        end

        false
      end

      # Server management
      def register_server(name : String, description : String, hopcount : Int32,
                          token : String? = nil, link_server : LinkServer? = nil) : Domain::Server
        server = Domain::Server.new(name, description, hopcount, token, link_server)
        add(name, server)
        server
      end

      def add_user_to_server(server_name : String, nickname : String) : Bool
        if server = get(server_name)
          server.add_user(nickname)
          true
        else
          false
        end
      end

      def remove_user_from_server(server_name : String, nickname : String) : Bool
        if server = get(server_name)
          server.remove_user(nickname)
          true
        else
          false
        end
      end

      # Query methods
      def find_local_servers : Array(Domain::Server)
        @@servers.values.select(&.is_local?)
      end

      def find_remote_servers : Array(Domain::Server)
        @@servers.values.reject(&.is_local?)
      end

      def find_servers_by_pattern(pattern : String) : Array(Domain::Server)
        regex = Regex.new(pattern.gsub("*", ".*"))
        @@servers.values.select(&.name.matches?(regex))
      end

      def get_server_by_token(token : String) : Domain::Server?
        @@servers.values.find { |server| server.token == token }
      end

      def link_servers : Array(LinkServer)
        @@servers.values.compact_map(&.link_server)
      end

      def find_server_for_user(nickname : String) : Domain::Server?
        @@servers.values.find(&.users.includes?(nickname))
      end

      # Network statistics
      def network_statistics : Hash(Symbol, Int32)
        total_users = @@servers.values.sum(&.user_count)
        local_servers = find_local_servers.size
        remote_servers = find_remote_servers.size

        {
          servers:        size,
          local_servers:  local_servers,
          remote_servers: remote_servers,
          total_users:    total_users,
          connections:    @@topology.values.sum(&.size) / 2, # Each connection counted twice
        }
      end

      def server_list(mask : String = "*") : Array(Domain::Server)
        if mask == "*"
          all
        else
          find_servers_by_pattern(mask)
        end
      end

      # Topology visualization (for debugging)
      def topology_map : Hash(String, Array(String))
        result = Hash(String, Array(String)).new
        @@topology.each do |server, connections|
          result[server] = connections.to_a
        end
        result
      end

      # Server health monitoring
      def update_ping_time(server_name : String, ping_time : Time) : Bool
        if server = get(server_name)
          server.ping_time = ping_time
          true
        else
          false
        end
      end

      def get_ping_time(server_name : String) : Time?
        get(server_name).try(&.ping_time)
      end
    end
  end
end
