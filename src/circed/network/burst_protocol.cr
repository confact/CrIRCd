require "../performance/metrics"

module Circed
  module Network
    # RFC 2813 compliant burst protocol implementation
    # Handles network state synchronization when servers connect
    class BurstProtocol
      # Perform complete network burst to newly connected server
      def self.send_burst(link_server : LinkServer)
        Log.info { "Starting network burst to #{link_server.name}" }

        Performance::Metrics.time_burst do
          # RFC 2813: Send information in this order:
          # 1. Known servers
          # 2. Client information
          # 3. Channel information

          send_server_burst(link_server)
          send_line_burst(link_server)
          send_user_burst(link_server)
          send_channel_burst(link_server)

          # End burst mode
          link_server.safe_send("EOB") # End of Burst
          Log.info { "Completed network burst to #{link_server.name}" }
        end
      rescue ex
        Log.error { "Failed to complete burst to #{link_server.name}: #{ex.message}" }
        raise ex
      end

      # Send all known servers to the connecting server
      private def self.send_server_burst(link_server : LinkServer)
        Log.debug { "Sending server burst to #{link_server.name}" }

        NetworkState.servers.each do |server_name, server_info|
          # Don't send the server its own information or the connecting server
          next if server_name == link_server.name || server_name == Server.name

          # Format: SERVER <servername> <hopcount> <token> :<description>
          token = server_info.token || "0"
          hopcount = server_info.hopcount + 1 # Add one hop through us

          link_server.safe_send("SERVER #{server_name} #{hopcount} #{token} :#{server_info.description}")
        end
      end

      private def self.send_line_burst(link_server : LinkServer) : Nil
        Log.debug { "Sending line burst to #{link_server.name}" }

        LineState.each do |line|
          next unless line.type == Domain::LineBan::GLINE

          link_server.safe_send(line.server_message)
        end
      end

      # Send all known users to the connecting server
      private def self.send_user_burst(link_server : LinkServer) : Nil
        Log.debug { "Sending user burst to #{link_server.name}" }

        target_server_name = link_server.name

        NetworkState.users.each_value do |user_info|
          next if user_info.server == target_server_name

          nickname = user_info.nickname
          hopcount = user_info.hopcount + 1
          modes = Utils::IrcUtils.mode_string(user_info.modes)

          capacity = 20 + nickname.size + user_info.username.size + user_info.hostname.size +
                     user_info.server.size + modes.size + user_info.realname.size

          message = String.build(capacity: capacity) do |io|
            io << "NICK " << nickname << ' ' << hopcount << ' ' << user_info.connected_at.to_unix << ' '
            io << user_info.username << ' ' << user_info.hostname << ' '
            io << user_info.server << ' ' << modes << " :" << user_info.realname
          end

          link_server.safe_send(message)

          if away_msg = user_info.away_message
            link_server.safe_send("AWAY #{nickname} :#{away_msg}")
          end
        end
      end

      # Send all known channels to the connecting server using NJOIN
      private def self.send_channel_burst(link_server : LinkServer)
        Log.debug { "Sending channel burst to #{link_server.name}" }

        NetworkState.channels.each_value do |channel_info|
          next if channel_info.members.empty?

          channel_name = channel_info.name
          send_njoin_burst(link_server, channel_name, channel_info)
          send_channel_mode_parameters(link_server, channel_name, channel_info)

          if topic = channel_info.topic
            topic_by = channel_info.topic_set_by || Server.name
            topic_at = channel_info.topic_set_at || channel_info.created_at
            link_server.safe_send(
              "TOPIC #{channel_name} #{channel_info.created_at.to_unix} #{topic_at.to_unix} #{topic_by} :#{topic}"
            )
          end
        end
      end

      private def self.send_channel_mode_parameters(link_server : LinkServer, channel_name : String,
                                                    channel : NetworkState::ChannelInfo) : Nil
        timestamp = channel.created_at.to_unix
        link_server.safe_send("MODE #{channel_name} #{timestamp} +k #{channel.password}") if channel.password
        link_server.safe_send("MODE #{channel_name} #{timestamp} +l #{channel.user_limit}") if channel.user_limit
        channel.ban_list.each do |mask|
          link_server.safe_send("MODE #{channel_name} #{timestamp} +b #{mask}")
        end
      end

      private def self.send_njoin_burst(link_server : LinkServer, channel_name : String, channel_info : NetworkState::ChannelInfo) : Nil
        members_by_modes = Hash(Set(Char), IO::Memory).new

        channel_info.members.each do |nickname, modes|
          next if user_on_server?(nickname, link_server.name)

          nicknames = members_by_modes.put_if_absent(modes) { IO::Memory.new }
          nicknames << ' ' unless nicknames.empty?
          nicknames << nickname
        end

        members_by_modes.each do |modes, nicknames|
          link_server.safe_send(build_njoin_message(channel_name, channel_info, modes, nicknames))
        end
      end

      private def self.build_njoin_message(channel_name : String, channel : NetworkState::ChannelInfo,
                                           member_modes : Set(Char), nicknames : IO::Memory) : String
        String.build do |io|
          io << "NJOIN " << channel_name << ' ' << channel.created_at.to_unix << ' '
          io << Utils::IrcUtils.mode_string(channel.modes) << ' '
          if member_modes.empty?
            io << '+'
          else
            io << '+'
            member_modes.each { |mode| io << mode }
          end
          io << " :" << nicknames
        end
      end

      private def self.user_on_server?(nickname : String, server_name : String) : Bool
        user = NetworkState.get_user(nickname)
        !user.nil? && user.server == server_name
      end

      # Process received burst data from another server
      def self.process_burst_message(command : String, params : Array(String), link_server : LinkServer)
        case command
        when "SERVER"
          process_burst_server(params, link_server)
        when "NICK"
          process_burst_nick(params, link_server)
        when "NJOIN"
          process_burst_njoin(params, link_server)
        when "TOPIC"
          process_burst_topic(params, link_server)
        when "MODE"
          process_burst_mode(params, link_server)
        when "AWAY"
          process_burst_away(params, link_server)
        when Domain::LineBan::GLINE
          Commands::ServerCommands.gline(link_server, params)
        when "EOB"
          process_end_of_burst(link_server)
        end
      end

      private def self.process_burst_server(params : Array(String), link_server : LinkServer)
        return if params.size < 4

        server_name = params[0]
        hopcount = params[1].to_i? || 0
        token = params[2]
        description = Utils::IrcUtils.trailing_param(params, 3)

        unless NetworkState.add_server(server_name, hopcount, description, nil, token) &&
               NetworkState.add_server_link(link_server.name, server_name)
          link_server.close("Server #{server_name} already exists")
          return
        end

        Log.debug { "Received server #{server_name} in burst from #{link_server.name}" }
      end

      private def self.process_burst_nick(params : Array(String), link_server : LinkServer)
        return if params.size < 8

        nickname = params[0]
        hopcount = params[1].to_i? || 0
        connected_at = Time.unix(params[2].to_i64? || Time.utc.to_unix)
        username = params[3]
        hostname = params[4]
        server_name = params[5]
        modes = params[6]
        realname = Utils::IrcUtils.trailing_param(params, 7)

        return unless NetworkState.add_user(nickname, username, hostname, realname, server_name, hopcount, connected_at)

        # Process user modes
        if modes.starts_with?('+')
          user = NetworkState.get_user(nickname)
          modes.each_char { |mode| user.try(&.modes.<<(mode)) unless mode == '+' }
        end

        Log.debug { "Received user #{nickname} in burst from #{link_server.name}" }
      end

      private def self.process_burst_njoin(params : Array(String), link_server : LinkServer)
        return if params.size < 5

        channel_name = params[0]
        created_at = Time.unix(params[1].to_i64? || Time.utc.to_unix)
        channel_modes = Utils::IrcUtils.mode_set(params[2])
        member_modes = Utils::IrcUtils.mode_set(params[3])
        nicknames_str = Utils::IrcUtils.trailing_param(params, 4)

        accept_member_modes = NetworkState.merge_channel(channel_name, created_at, channel_modes)
        nickname_count = 0
        nicknames_str.split do |nickname|
          nickname_count += 1
          modes = accept_member_modes ? member_modes.dup : Set(Char).new
          NetworkState.join_user_to_channel(nickname, channel_name, modes)
        end
        NetworkState.sync_channel_repository(channel_name)

        Log.debug { "Received NJOIN for #{channel_name} with #{nickname_count} users from #{link_server.name}" }
      end

      private def self.process_burst_topic(params : Array(String), link_server : LinkServer)
        return if params.size < 5

        channel_name = params[0]
        channel_created_at = Time.unix(params[1].to_i64? || 0_i64)
        topic_set_at = Time.unix(params[2].to_i64? || 0_i64)
        topic_by = params[3]
        topic = Utils::IrcUtils.trailing_param(params, 4)

        if NetworkState.set_channel_topic(channel_name, topic, topic_by, topic_set_at, channel_created_at)
          NetworkState.sync_channel_repository(channel_name)
        end

        Log.debug { "Received topic for #{channel_name} from #{link_server.name}" }
      end

      private def self.process_burst_mode(params : Array(String), link_server : LinkServer)
        return if params.size < 3

        target = params[0]
        created_at = Time.unix(params[1].to_i64? || 0_i64)
        modes = params[2]

        if Utils::IrcUtils.valid_channel_name?(target)
          NetworkState.apply_channel_modes(target, modes, params, created_at, 3)
        end
      end

      private def self.process_burst_away(params : Array(String), link_server : LinkServer)
        return if params.size < 2

        nickname = params[0]
        away_msg = Utils::IrcUtils.trailing_param(params, 1)

        NetworkState.set_user_away(nickname, away_msg.empty? ? nil : away_msg)

        Log.debug { "Received away status for #{nickname} from #{link_server.name}" }
      end

      private def self.process_end_of_burst(link_server : LinkServer)
        Log.info { "Received end of burst from #{link_server.name}" }
      end
    end
  end
end
