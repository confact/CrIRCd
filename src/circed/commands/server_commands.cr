require "../performance/metrics"

module Circed
  module Commands
    # RFC 2813 server-to-server commands
    module ServerCommands
      # SQUIT - Server Quit
      # Format: SQUIT <server> :<comment>
      def self.squit(link_server : LinkServer, params : Array(String)) : Nil
        return if params.empty?

        Performance::Metrics.time_netsplit do
          server_name = params[0]
          comment = Utils::IrcUtils.trailing_param(params, 1, "No reason")
          return unless Network::NetworkState.get_server(server_name)

          Log.info { "Received SQUIT for #{server_name}: #{comment}" }

          # Forward SQUIT to other servers first (before removing from state)
          forward_to_servers(link_server, "SQUIT", params)

          Network::NetworkState.remove_server(server_name, send_squit: false)

          if server_name == link_server.name
            link_server.close_from_peer("Received SQUIT: #{comment}")
          end
        end
      end

      # KILL - Kill user connection
      # Format: KILL <nickname> :<comment>
      def self.kill(link_server : LinkServer, params : Array(String)) : Nil
        return if params.size < 2

        nickname = params[0]
        comment = Utils::IrcUtils.trailing_param(params, 1, "Killed")

        Log.info { "Received KILL for #{nickname}: #{comment}" }

        Network::NetworkState.remove_user(nickname)

        forward_to_servers(link_server, "KILL", params)

        if local_client = Infrastructure::ServiceLocator.user_repository.get_client(nickname)
          local_client.send_error("Killed: #{comment}")
          local_client.close
        end
      end

      # WALLOPS - Send an operator wall notice from a server
      # Format: WALLOPS :<message>
      def self.wallops(link_server : LinkServer, params : Array(String)) : Nil
        return if params.empty?

        message = Utils::IrcUtils.trailing_param(params, 0)
        source = link_server.name.empty? ? link_server.target_host : link_server.name
        wallops_message = ":#{source} WALLOPS :#{message}"
        user_repository = Infrastructure::ServiceLocator.user_repository

        user_repository.each_client do |client|
          next unless nickname = client.nickname
          next unless user = user_repository[nickname]?
          next unless user.modes.includes?('w')

          client.send_message(wallops_message)
        end

        forward_to_servers(link_server, "WALLOPS", params)
      end

      # GLINE - Network-wide user@host ban extension
      # Add format: GLINE <mask> <expires-unix|0> <set-by> :<reason>
      # Remove format: GLINE <mask>
      def self.gline(link_server : LinkServer, params : Array(String)) : Nil
        return if params.empty?

        if params.size == 1
          mask = Network::LineState.normalize_mask(Domain::LineBan::GLINE, params[0])
          return unless Network::LineState.remove(Domain::LineBan::GLINE, mask)

          forward_to_servers(link_server, "#{Domain::LineBan::GLINE} #{mask}")
          return
        end

        return if params.size < 4

        mask = params[0]
        expires_at = params[1].to_i64?
        set_by = params[2]
        reason = Utils::IrcUtils.trailing_param(params, 3, "No reason given")
        return if expires_at && expires_at > 0 && expires_at <= Time.utc.to_unix

        line = Network::LineState.add_until(Domain::LineBan::GLINE, mask, reason, set_by, expires_at && expires_at > 0 ? Time.unix(expires_at) : nil)
        return unless line

        Network::LineState.enforce(line)
        forward_to_servers(link_server, line.server_message)
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
        command_counts = Performance::Metrics.command_counts
        command_counts.keys.sort!.each do |command|
          client.send_message(
            Server.clean_name,
            "212",
            client.nickname || "*",
            command,
            command_counts[command].to_s,
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

          client.send_message(Server.clean_name, "256", nick, Server.name, ":Administrative info")
          client.send_message(Server.clean_name, "257", nick, ":Circed IRC Server")
          client.send_message(Server.clean_name, "258", nick, ":Server Location")
          client.send_message(Server.clean_name, "259", nick, ":admin@#{Server.config.host}")
        end
      end

      # NJOIN - Efficient channel join for burst
      # Format: NJOIN <channel> <created-at> <channel-modes> <member-modes> :<nicknames>
      def self.njoin(link_server : LinkServer, params : Array(String)) : Nil
        return if params.size < 5

        Performance::Metrics.time_message_processing do
          channel_name = params[0]
          created_at = Time.unix(params[1].to_i64? || Time.utc.to_unix)
          channel_modes = Utils::IrcUtils.mode_set(params[2])
          member_modes = Utils::IrcUtils.mode_set(params[3])
          nicknames_str = Utils::IrcUtils.trailing_param(params, 4)

          nicknames = nicknames_str.split
          accept_member_modes = Network::NetworkState.merge_channel(channel_name, created_at, channel_modes)
          nicknames.each do |nickname|
            next unless Network::NetworkState.user_routed_through?(nickname, link_server.name)

            modes = accept_member_modes ? member_modes.dup : Set(Char).new
            Network::NetworkState.join_user_to_channel(nickname, channel_name, modes)
          end
          Network::NetworkState.sync_channel_repository(channel_name)

          forward_to_servers(link_server, "NJOIN", params)

          notify_local_users_njoin(channel_name, nicknames)

          Performance::Metrics.increment_channel_operations
          Performance::Metrics.increment_messages(nicknames.size.to_u64)
        end
      end

      private def self.forward_to_servers(sender : LinkServer, command : String, params : Array(String)) : Nil
        forward_to_servers(sender, FastIRC::Message.new(command, params).to_s)
      end

      private def self.forward_to_servers(sender : LinkServer, message : String) : Nil
        ServerHandler.servers.each do |server|
          next if server == sender

          server.send_message(message)
        end
      end

      private def self.notify_local_users_njoin(channel_name : String, nicknames : Array(String)) : Nil
        Log.debug { "Notifying local users about NJOIN in #{channel_name}" }

        return unless channel = Network::NetworkState.get_channel(channel_name)

        user_repository = Infrastructure::ServiceLocator.user_repository

        nicknames.each do |joining_nick|
          next unless user_info = Network::NetworkState.get_user(joining_nick)

          join_message = ":#{joining_nick}!#{user_info.username}@#{user_info.hostname} JOIN #{channel_name}"

          channel.members.each_key do |nick|
            if client = user_repository.get_client(nick)
              client.send_message(join_message)
            end
          end
        end
      end

      private def self.route_command_or_execute(client : Client, command : String, target : String?, &)
        unless target && target != Server.name
          yield
          return
        end

        if route = Network::NetworkState.route_to_server(target)
          if target_server = ServerHandler.servers.find { |server| server.name == route }
            target_server.send_message("#{command} #{target}")
            return
          end
        end

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
