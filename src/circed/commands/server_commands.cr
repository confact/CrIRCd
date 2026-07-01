require "../performance/metrics"

module Circed
  module Commands
    # RFC 2813 server-to-server commands - performance optimized
    module ServerCommands
      # SQUIT - Server Quit
      # Format: SQUIT <server> :<comment>
      def self.squit(link_server : LinkServer, params : Array(String)) : Nil
        return if params.empty?

        Performance::Metrics.time_netsplit do
          server_name = params[0]
          comment = params[1..]?.try(&.join(' ')) || "No reason"
          comment = comment.lstrip(':')

          Log.info { "Received SQUIT for #{server_name}: #{comment}" }

          # Forward SQUIT to other servers first (before removing from state)
          forward_to_servers(link_server, "SQUIT", params)

          # Remove server from network state (this handles transitive disconnections)
          Network::NetworkState.remove_server(server_name, send_squit: false) # Don't send SQUIT again

          # If it's our direct connection, close it
          if server_name == link_server.name
            link_server.close("Received SQUIT: #{comment}")
          end

          # Update metrics
          Performance::Metrics.decrement_server_connections
        end
      end

      # KILL - Kill user connection
      # Format: KILL <nickname> :<comment>
      def self.kill(link_server : LinkServer, params : Array(String)) : Nil
        return if params.size < 2

        nickname = params[0]
        comment = params[1..]?.try(&.join(' ')) || "Killed"
        comment = comment.lstrip(':')

        Log.info { "Received KILL for #{nickname}: #{comment}" }

        # Remove user from network state
        Network::NetworkState.remove_user(nickname)

        # Forward KILL to other servers
        forward_to_servers(link_server, "KILL", params)

        # If it's a local user, disconnect them
        if local_client = find_local_client(nickname)
          local_client.send_error("Killed: #{comment}")
          local_client.close
        end
      end

      # LINKS - Server list query
      # Format: LINKS [<remote server>] [<server mask>]
      def self.links(client : Client, params : Array(String))
        mask = params[0]? || "*"

        server_list = Network::NetworkState.server_list(mask)

        server_list.each do |server|
          # 364 RPL_LINKS
          # Format: <mask> <server> :<hopcount> <server info>
          client.send_message(
            Server.clean_name,
            "364",
            client.nickname || "*",
            mask,
            server.name,
            ":#{server.hopcount} #{server.description}"
          )
        end

        # 365 RPL_ENDOFLINKS
        client.send_message(
          Server.clean_name,
          "365",
          client.nickname || "*",
          mask,
          ":End of LINKS list"
        )
      end

      # STATS - Server statistics
      # Format: STATS [<query>] [<target>]
      def self.stats(client : Client, params : Array(String))
        query = params[0]? || "u"

        case query.downcase
        when "u"
          send_uptime_stats(client)
        when "l"
          send_link_stats(client)
        when "m"
          send_command_stats(client)
        when "o"
          send_operator_stats(client)
        end

        send_stats_end(client, query)
      end

      private def self.send_uptime_stats(client : Client)
        client.send_message(
          Server.clean_name,
          "242",
          client.nickname || "*",
          ":Server Up: #{Time.utc - Server.start_time}"
        )
      end

      private def self.send_link_stats(client : Client)
        stats = Network::NetworkState.stats
        client.send_message(
          Server.clean_name,
          "211",
          client.nickname || "*",
          "servers",
          "#{stats[:servers]}",
          "0",
          "0",
          "#{stats[:connections]}"
        )
      end

      private def self.send_command_stats(client : Client)
        Performance::Metrics.command_counts.to_a.sort_by(&.[0]).each do |command, count|
          client.send_message(
            Server.clean_name,
            "212",
            client.nickname || "*",
            command,
            count.to_s,
            "0",
            "0"
          )
        end
      end

      private def self.send_operator_stats(client : Client)
        client.send_message(
          Server.clean_name,
          "243",
          client.nickname || "*",
          "O",
          "*@*",
          "operators",
          "0",
          "Operator"
        )
      end

      private def self.send_stats_end(client : Client, query : String)
        client.send_message(
          Server.clean_name,
          "219",
          client.nickname || "*",
          query,
          ":End of STATS report"
        )
      end

      # TIME - Server time
      # Format: TIME [<target>]
      def self.time(client : Client, params : Array(String))
        target = params[0]?

        route_command_or_execute(client, "TIME", target) do
          # 391 RPL_TIME
          current_time = Time.utc
          client.send_message(
            Server.clean_name,
            "391",
            client.nickname || "*",
            Server.name,
            ":#{current_time.to_s("%a %b %d %H:%M:%S %Y")}"
          )
        end
      end

      # VERSION - Server version
      # Format: VERSION [<target>]
      def self.version(client : Client, params : Array(String))
        target = params[0]?

        route_command_or_execute(client, "VERSION", target) do
          # 351 RPL_VERSION
          client.send_message(
            Server.clean_name,
            "351",
            client.nickname || "*",
            "#{Circed::VERSION}",
            Server.name,
            ":Circed IRC Server"
          )
        end
      end

      # ADMIN - Administrative information
      # Format: ADMIN [<target>]
      def self.admin(client : Client, params : Array(String))
        target = params[0]?

        route_command_or_execute(client, "ADMIN", target) do
          nick = client.nickname || "*"

          # Send admin info responses
          [
            ["256", Server.name, ":Administrative info"],
            ["257", ":Circed IRC Server"],
            ["258", ":Server Location"],
            ["259", ":admin@#{Server.config.host}"],
          ].each do |code, *data|
            client.send_message(Server.clean_name, code, nick, *data)
          end
        end
      end

      # NJOIN - Efficient channel join for burst
      # Format: NJOIN <channel> <modes> :<nicknames>
      def self.njoin(link_server : LinkServer, params : Array(String)) : Nil
        return if params.size < 3

        Performance::Metrics.time_message_processing do
          channel_name = params[0]
          modes_str = params[1]
          nicknames_str = params[2..]?.try(&.join(' ')) || ""
          nicknames_str = nicknames_str.lstrip(':')

          # Split with better performance for large user lists
          nicknames = nicknames_str.split(limit: 100) # Reasonable limit for batch joins

          # Parse user modes in channel with pre-allocated set
          user_modes = Set(Char).new(initial_capacity: 4)
          if modes_str.starts_with?('+')
            modes_str.each_char_with_index do |char, index|
              next if index == 0 # Skip the '+'
              user_modes << char
            end
          end

          Log.debug { "NJOIN: #{nicknames.size} users joining #{channel_name} with modes #{modes_str}" }

          # Add users to channel in network state
          Network::NetworkState.add_channel(channel_name)
          nicknames.each do |nickname|
            Network::NetworkState.join_user_to_channel(nickname, channel_name, user_modes.dup)
          end

          # Forward to other servers (except sender)
          forward_to_servers(link_server, "NJOIN", params)

          # Notify local users in channel
          notify_local_users_njoin(channel_name, nicknames, user_modes)

          # Update metrics
          Performance::Metrics.increment_channel_operations
          Performance::Metrics.increment_messages(nicknames.size.to_u64)
        end
      end

      # Helper methods

      private def self.forward_to_servers(sender : LinkServer, command : String, params : Array(String)) : Nil
        message = String.build do |io|
          io << command << ' ' << params.join(' ')
        end

        ServerHandler.servers.each do |server|
          next if server == sender
          server.send_message(message)
        end
      end

      private def self.find_local_client(nickname : String) : Client?
        user_repository = Infrastructure::ServiceLocator.user_repository
        user_repository.get_client(nickname)
      end

      private def self.find_server_connection(server_name : String) : LinkServer?
        ServerHandler.servers.find { |server| server.name == server_name }
      end

      private def self.notify_local_users_njoin(channel_name : String, nicknames : Array(String), modes : Set(Char)) : Nil
        Log.debug { "Notifying local users about NJOIN in #{channel_name}" }

        return unless channel = Network::NetworkState.get_channel(channel_name)

        user_repository = Infrastructure::ServiceLocator.user_repository

        # Collect local users once
        local_clients = channel.members.keys.compact_map do |nick|
          user_repository.get_client(nick)
        end

        return if local_clients.empty?

        # Build and send JOIN messages
        nicknames.each do |joining_nick|
          next unless user_info = Network::NetworkState.get_user(joining_nick)

          join_message = format_user_join(joining_nick, user_info, channel_name)

          # Send to all local users in the channel
          local_clients.each do |client|
            client.send_message(join_message)
          end
        end
      end

      private def self.format_user_join(nickname : String, user_info : Network::NetworkState::UserInfo, channel_name : String) : String
        # Format: ":nick!user@host JOIN #channel"
        hostmask = "#{nickname}!#{user_info.username}@#{user_info.hostname}"
        ":#{hostmask} JOIN #{channel_name}"
      end

      # Extract common server routing pattern
      private def self.route_command_or_execute(client : Client, command : String, target : String?, &)
        if target && target != Server.name
          # Forward to target server
          if route = Network::NetworkState.route_to_server(target)
            if target_server = find_server_connection(route)
              target_server.send_message("#{command} #{target}")
              return
            end
          end

          # Server not found
          send_no_such_server_error(client, target)
        else
          yield # Execute local command
        end
      end

      private def self.send_no_such_server_error(client : Client, target : String)
        client.send_message(
          Server.clean_name,
          "402",
          client.nickname || "*",
          target,
          ":No such server"
        )
      end
    end
  end
end
