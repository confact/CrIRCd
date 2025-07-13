module Circed
  module Network
    # RFC 2813 compliant burst protocol implementation
    # Handles network state synchronization when servers connect
    class BurstProtocol
      include SocketHelper

      # Perform complete network burst to newly connected server
      def self.send_burst(link_server : LinkServer)
        Log.info { "Starting network burst to #{link_server.name}" }
        
        begin
          # RFC 2813: Send information in this order:
          # 1. Known servers
          # 2. Client information  
          # 3. Channel information
          
          send_server_burst(link_server)
          send_user_burst(link_server)
          send_channel_burst(link_server)
          
          # End burst mode
          link_server.safe_send("EOB")  # End of Burst
          Log.info { "Completed network burst to #{link_server.name}" }
          
        rescue ex
          Log.error { "Failed to complete burst to #{link_server.name}: #{ex.message}" }
          raise ex
        end
      end

      # Send all known servers to the connecting server
      private def self.send_server_burst(link_server : LinkServer)
        Log.debug { "Sending server burst to #{link_server.name}" }
        
        NetworkState.servers.each do |server_name, server_info|
          # Don't send the server its own information or the connecting server
          next if server_name == link_server.name || server_name == Server.name
          
          # Format: SERVER <servername> <hopcount> <token> :<description>
          token = server_info.token || "0"
          hopcount = server_info.hopcount + 1  # Add one hop through us
          
          message = build_irc_message("SERVER", [server_name, hopcount.to_s, token, ":#{server_info.description}"])
          link_server.safe_send(message)
        end
        
        # Send our own server information if not already sent
        our_token = generate_server_token(Server.name)
        our_desc = "Circed IRC Server"
        message = "SERVER #{Server.name} 1 #{our_token} :#{our_desc}"
        link_server.safe_send(message)
      end

      # Send all known users to the connecting server
      private def self.send_user_burst(link_server : LinkServer)
        Log.debug { "Sending user burst to #{link_server.name}" }
        
        NetworkState.users.each do |nickname, user_info|
          # Don't send users that are on the connecting server
          next if user_info.server == link_server.name
          
          # Format: NICK <nickname> <hopcount> <username> <hostname> <servertoken> <usermodes> :<realname>
          hopcount = user_info.hopcount + 1
          server_token = get_server_token(user_info.server)
          modes = user_info.modes.empty? ? "+" : "+#{user_info.modes.join("")}"
          
          message = "NICK #{nickname} #{hopcount} #{user_info.username} #{user_info.hostname} #{server_token} #{modes} :#{user_info.realname}"
          link_server.safe_send(message)
          
          # Send away message if user is away
          if away_msg = user_info.away_message
            link_server.safe_send("AWAY #{nickname} :#{away_msg}")
          end
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
      private def self.send_njoin_burst(link_server : LinkServer, channel_name : String, channel_info : NetworkState::ChannelInfo)
        # Group members by their modes for efficient NJOIN
        members_by_modes = Hash(Set(Char), Array(String)).new
        
        channel_info.members.each do |nickname, modes|
          members_by_modes[modes] ||= Array(String).new
          members_by_modes[modes] << nickname
        end
        
        # Send NJOIN for each mode group
        members_by_modes.each do |modes, nicknames|
          # Don't send users that are on the connecting server
          filtered_nicks = nicknames.reject do |nick|
            user = NetworkState.get_user(nick)
            user && user.server == link_server.name
          end
          
          next if filtered_nicks.empty?
          
          # Format: NJOIN <channel> <modes> :nickname1 nickname2 nickname3
          mode_prefix = modes.empty? ? "" : "+#{modes.join("")}"
          nicks_list = filtered_nicks.join(" ")
          
          message = "NJOIN #{channel_name} #{mode_prefix} :#{nicks_list}"
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
        
        if channel = NetworkState.get_channel(channel_name)
          channel.topic = topic
          channel.topic_set_by = topic_by
          channel.topic_set_at = Time.utc
        end
        
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
        
        if user = NetworkState.get_user(nickname)
          user.away_message = away_msg.empty? ? nil : away_msg
        end
        
        Log.debug { "Received away status for #{nickname} from #{link_server.name}" }
      end

      private def self.process_end_of_burst(link_server : LinkServer)
        Log.info { "Received end of burst from #{link_server.name}" }
        # Mark server as fully synchronized
        if server = NetworkState.get_server(link_server.name)
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