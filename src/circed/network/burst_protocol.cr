require "../performance/metrics"

module Circed
  module Network
    # RFC 2813 compliant burst protocol implementation - performance optimized
    # Handles network state synchronization when servers connect
    class BurstProtocol
      include SocketHelper

      # Perform complete network burst to newly connected server
      def self.send_burst(link_server : LinkServer)
        Log.info { "Starting network burst to #{link_server.name}" }

        Performance::Metrics.time_burst do
          # RFC 2813: Send information in this order:
          # 1. Known servers
          # 2. Client information
          # 3. Channel information

          send_server_burst(link_server)
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

          message = build_irc_message("SERVER", [server_name, hopcount.to_s, token, ":#{server_info.description}"])
          link_server.safe_send(message)
        end

        # Send our own server information if not already sent
        our_token = generate_server_token(Server.name)
        our_desc = "Circed IRC Server"
        message = "SERVER #{Server.name} 1 #{our_token} :#{our_desc}"
        link_server.safe_send(message)
      end

      # Send all known users to the connecting server - optimized
      private def self.send_user_burst(link_server : LinkServer) : Nil
        Log.debug { "Sending user burst to #{link_server.name}" }

        # Pre-allocate collections for better performance
        away_users = [] of {String, String}  # Collect away users for batch sending
        target_server_name = link_server.name

        NetworkState.users.each do |nickname, user_info|
          # Skip users on the connecting server
          next if user_info.server == target_server_name

          # Build NICK message efficiently with calculated capacity
          hopcount = user_info.hopcount + 1
          server_token = get_server_token(user_info.server)
          modes = user_info.modes.empty? ? "+" : "+#{user_info.modes.join}"

          # Pre-calculate message size for optimal String.build performance
          capacity = 20 + nickname.size + user_info.username.size + user_info.hostname.size +
                    server_token.size + modes.size + user_info.realname.size

          message = String.build(capacity: capacity) do |io|
            io << "NICK " << nickname << ' ' << hopcount << ' '
            io << user_info.username << ' ' << user_info.hostname << ' '
            io << server_token << ' ' << modes << " :" << user_info.realname
          end

          link_server.safe_send(message)

          # Collect away users for batch processing
          if away_msg = user_info.away_message
            away_users << {nickname, away_msg}
          end
        end

        # Send away messages in batch to reduce system calls
        away_users.each do |(nickname, away_msg)|
          link_server.safe_send("AWAY #{nickname} :#{away_msg}")
        end
      end

      # Send all known channels to the connecting server using NJOIN
      private def self.send_channel_burst(link_server : LinkServer)
        Log.debug { "Sending channel burst to #{link_server.name}" }

        NetworkState.channels.each do |channel_name, channel_info|
          # Skip empty channels
          next if channel_info.members.empty?

          # Send channel modes first if any
          unless channel_info.modes.empty?
            modes = "+#{channel_info.modes.join("")}"
            link_server.safe_send("MODE #{channel_name} #{modes}")
          end

          # Send topic if set
          if topic = channel_info.topic
            if topic_by = channel_info.topic_set_by
              link_server.safe_send("TOPIC #{channel_name} #{topic_by} :#{topic}")
            else
              link_server.safe_send("TOPIC #{channel_name} :#{topic}")
            end
          end

          # Send channel members using NJOIN (more efficient than individual JOINs)
          send_njoin_burst(link_server, channel_name, channel_info)
        end
      end

      # Send NJOIN command for efficient channel member synchronization
      private def self.send_njoin_burst(link_server : LinkServer, channel_name : String, channel_info : NetworkState::ChannelInfo) : Nil
        # Group members by their modes for efficient NJOIN
        members_by_modes = Hash(Set(Char), Array(String)).new { |h, k| h[k] = [] of String }

        channel_info.members.each do |nickname, modes|
          members_by_modes[modes] << nickname
        end

        # Send NJOIN for each mode group
        members_by_modes.each do |modes, nicknames|
          # Filter out users on the connecting server
          filtered_nicks = nicknames.reject do |nick|
            if user = NetworkState.get_user(nick)
              user.server == link_server.name
            else
              false
            end
          end

          next if filtered_nicks.empty?

          # Build NJOIN message efficiently
          message = String.build do |io|
            io << "NJOIN " << channel_name << ' '
            io << '+' << modes.join unless modes.empty?
            io << " :" << filtered_nicks.join(' ')
          end
          link_server.safe_send(message)
        end
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
        when "EOB"
          process_end_of_burst(link_server)
        end
      end

      private def self.process_burst_server(params : Array(String), link_server : LinkServer)
        return if params.size < 4

        server_name = params[0]
        hopcount = params[1].to_i? || 0
        token = params[2]
        description = extract_colon_prefixed_text(params, 3)

        NetworkState.add_server(server_name, hopcount, description, nil, token)
        NetworkState.add_server_link(link_server.name, server_name)

        Log.debug { "Received server #{server_name} in burst from #{link_server.name}" }
      end

      private def self.process_burst_nick(params : Array(String), link_server : LinkServer)
        return if params.size < 7

        nickname = params[0]
        hopcount = params[1].to_i? || 0
        username = params[2]
        hostname = params[3]
        server_token = params[4]
        modes = params[5]
        realname = extract_colon_prefixed_text(params, 6)

        # Find server by token
        server_name = find_server_by_token(server_token) || link_server.name

        NetworkState.add_user(nickname, username, hostname, realname, server_name, hopcount)

        # Process user modes
        if modes.starts_with?('+')
          user = NetworkState.get_user(nickname)
          modes[1..].each_char { |mode| user.try(&.modes.<<(mode)) }
        end

        Log.debug { "Received user #{nickname} in burst from #{link_server.name}" }
      end

      private def self.process_burst_njoin(params : Array(String), link_server : LinkServer)
        return if params.size < 3

        channel_name = params[0]
        modes_str = params[1]
        nicknames_str = extract_colon_prefixed_text(params, 2)

        nicknames = nicknames_str.split(' ')

        # Parse modes
        user_modes = Set(Char).new
        if modes_str.starts_with?('+')
          modes_str[1..].each_char { |mode| user_modes << mode }
        end

        # Add users to channel
        NetworkState.add_channel(channel_name)
        nicknames.each do |nickname|
          NetworkState.join_user_to_channel(nickname, channel_name, user_modes.dup)
        end

        Log.debug { "Received NJOIN for #{channel_name} with #{nicknames.size} users from #{link_server.name}" }
      end

      private def self.process_burst_topic(params : Array(String), link_server : LinkServer)
        return if params.size < 2

        channel_name = params[0]

        if params.size >= 3
          # TOPIC <channel> <who> :<topic>
          topic_by = params[1]
          topic = params[2..]?.try(&.join(" ")) || ""
          topic = topic.lstrip(':')
        else
          # TOPIC <channel> :<topic>
          topic_by = nil
          topic = params[1..]?.try(&.join(" ")) || ""
          topic = topic.lstrip(':')
        end

        NetworkState.set_channel_topic(channel_name, topic, topic_by)

        Log.debug { "Received topic for #{channel_name} from #{link_server.name}" }
      end

      private def self.process_burst_mode(params : Array(String), link_server : LinkServer)
        # Handle channel mode changes during burst
        return if params.size < 2

        target = params[0]
        modes = params[1]

        if target.starts_with?('#') || target.starts_with?('&')
          # Channel mode
          if channel = NetworkState.get_channel(target)
            parse_channel_modes(channel, modes)
          end
        end
      end

      private def self.process_burst_away(params : Array(String), link_server : LinkServer)
        return if params.size < 2

        nickname = params[0]
        away_msg = params[1..]?.try(&.join(" ")) || ""
        away_msg = away_msg.lstrip(':')

        NetworkState.set_user_away(nickname, away_msg.empty? ? nil : away_msg)

        Log.debug { "Received away status for #{nickname} from #{link_server.name}" }
      end

      private def self.process_end_of_burst(link_server : LinkServer)
        Log.info { "Received end of burst from #{link_server.name}" }
        # Mark server as fully synchronized
        NetworkState.get_server(link_server.name).try do |_|
          # Could add a "burst_complete" flag to ServerInfo if needed
        end
      end

      # Helper methods
      private def self.build_irc_message(command : String, params : Array(String), prefix : String? = nil) : String
        String.build do |io|
          io << ":#{prefix} " if prefix
          io << "#{command} #{params.join(" ")}"
        end
      end

      private def self.extract_colon_prefixed_text(params : Array(String), start_index : Int32) : String
        text = params[start_index..]?.try(&.join(" ")) || ""
        text.lstrip(':')
      end

      private def self.generate_server_token(server_name : String) : String
        # Simple token generation - in production this should be more sophisticated
        "#{server_name.hash.abs % 1000}"
      end

      private def self.get_server_token(server_name : String) : String
        server = NetworkState.get_server(server_name)
        server.try(&.token) || generate_server_token(server_name)
      end

      private def self.find_server_by_token(token : String) : String?
        NetworkState.servers.find { |_, server| server.token == token }.try(&.[0])
      end

      private def self.parse_channel_modes(channel : NetworkState::ChannelInfo, modes : String)
        adding = true
        modes.each_char do |char|
          case char
          when '+'
            adding = true
          when '-'
            adding = false
          else
            if adding
              channel.modes << char
            else
              channel.modes.delete(char)
            end
          end
        end
      end
    end
  end
end
