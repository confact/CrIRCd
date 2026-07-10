# Consolidated IRC service for common operations
# Handles both local operations and network-wide synchronization

require "../utils/irc_utils"

module Circed
  module Services
    class IRCService
      SELF_USER_MODES    = {'i', 'w'}
      CHANNEL_MODE_ORDER = {'p', 's', 'i', 'm', 'n', 't', 'k', 'l', 'b'}

      def initialize(@user_repository : Repositories::UserRepository,
                     @channel_repository : Repositories::ChannelRepository,
                     @notification_service : NotificationService)
      end

      # User joins a channel with proper validation, notifications, and network sync
      def join_channel(client : Client, channel_name : String, password : String? = nil) : Bool
        return false unless nickname = client.nickname

        # If client is not registered yet (no USER info), require registration before JOIN
        unless client.user
          client.send_message(Server.clean_name, Numerics::ERR_NOTREGISTERED, nickname, ":You have not registered")
          return false
        end

        # Basic format validation
        return false unless Utils::IrcUtils.validate_channel_name(client, channel_name)

        # Get or create channel
        channel = @channel_repository.create_channel(channel_name)

        # Already in channel?
        if channel.has_member?(nickname)
          Utils::IrcUtils.send_user_on_channel_error(client, channel_name)
          return false
        end

        # Validation checks
        unless validate_join_permissions(client, channel, password)
          return false
        end

        # Add user to channel
        @channel_repository.add_member(channel.name, nickname)
        channel.remove_invite(nickname)

        # Make first user an operator (before sending any messages)
        is_operator = false
        if channel.member_count == 1
          if modes = channel.member_modes?(nickname)
            modes << 'o'
            is_operator = true
          end
        end

        Network::NetworkState.sync_channel(channel)

        hostmask = client.hostmask || ""
        join_message = ":#{hostmask} JOIN #{channel_name}"

        # Send JOIN confirmation to the user (first message)
        client.send_message(join_message)

        # Send MODE message if user became operator (second message)
        if is_operator
          client.send_message(":#{hostmask} MODE #{channel_name} +o #{nickname}")
        end

        # Send topic if channel has one
        if topic = channel.topic
          client.send_message(Server.clean_name, Numerics::RPL_TOPIC, nickname, channel_name, ":#{topic}")
          if (topic_by = channel.topic_set_by) && (topic_time = channel.topic_set_at)
            client.send_message(Server.clean_name, Numerics::RPL_TOPICTIME, nickname, channel_name, topic_by, topic_time.to_unix.to_s)
          end
        end

        # Send NAMES list
        send_names_reply(client, channel)
        client.send_message(Server.clean_name, Numerics::RPL_ENDOFNAMES, nickname, channel.name, ":End of /NAMES list")

        # Send notifications to other users
        @notification_service.notify_channel(channel, join_message, nickname)

        # Propagate to network
        propagate_to_network(join_message)

        true
      end

      # User parts from a channel with network sync
      def part_channel(client : Client, channel_name : String, reason : String? = nil) : Bool
        return false unless nickname = client.nickname
        reason ||= nickname

        channel = @channel_repository[channel_name]?
        unless channel
          Utils::IrcUtils.send_no_such_channel_error(client, channel_name)
          return false
        end
        unless channel.has_member?(nickname)
          Utils::IrcUtils.send_not_on_channel_error(client, channel_name)
          return false
        end

        part_message = build_part_message(client, channel_name, reason)
        client.send_message(part_message)

        # Remove user from channel
        @channel_repository.part_user(channel.name, nickname)

        Network::NetworkState.part_user_from_channel(nickname, channel_name)

        # Send notifications to other channel members
        @notification_service.notify_channel(channel_name, part_message)

        propagate_to_network(part_message)

        true
      end

      # Handle user nickname changes with network sync
      def change_nickname(client : Client, new_nickname : String) : Bool
        return false unless old_nickname = client.nickname

        # Update repositories
        unless @user_repository.change_nickname(old_nickname, new_nickname)
          return false
        end

        # Update client's nickname
        client.nickname = new_nickname
        @channel_repository.rename_member(old_nickname, new_nickname)

        # Sync with network state
        sync_nick_with_network(old_nickname, new_nickname)

        # Send notifications and propagate the same wire message.
        if user = @user_repository[new_nickname]?
          message = ":#{old_nickname}!#{user.username}@#{user.hostname} NICK #{new_nickname}"
          client.send_message(message)
          @notification_service.notify_shared_channels(new_nickname, message)
          propagate_to_network(message)
        end

        true
      end

      # Handle user quit with network sync
      def quit_user(client : Client, reason : String? = nil) : Bool
        return false unless nickname = client.nickname
        reason ||= nickname

        quit_message = String.build do |io|
          io << ':' << (client.hostmask || nickname) << " QUIT"
          io << " :" << reason if reason
        end

        # Notify while channel membership is still indexed.
        @notification_service.notify_shared_channels(nickname, quit_message)

        # Remove from all channels
        @channel_repository.remove_user_from_all_channels(nickname)

        Network::NetworkState.remove_user(nickname)

        propagate_to_network(quit_message)

        # Remove from repositories
        @user_repository.delete(nickname)

        true
      end

      # Route messages to local or remote targets
      def route_message(sender : Client, target : String, message : String) : Bool
        sender_nick = sender.nickname
        return false unless sender_nick

        if Utils::IrcUtils.valid_channel_name?(target)
          # Channel message
          route_channel_message(sender, target, message)
        else
          # Private message
          route_private_message(sender, target, message)
        end
      end

      def route_notice(sender : Client, target : String, message : String) : Bool
        sender_nick = sender.nickname
        return false unless sender_nick

        if Utils::IrcUtils.valid_channel_name?(target)
          # Channel notice
          route_channel_notice(sender, target, message)
        else
          # Private notice
          route_private_notice(sender, target, message)
        end
      end

      # Set channel topic with validation and network sync
      def update_topic(client : Client, channel_name : String, topic : String) : Bool
        return false unless nickname = client.nickname
        return false unless channel = validate_topic_change(client, channel_name, nickname)

        # Set topic
        if topic.empty?
          channel.topic = nil
          channel.topic_set_by = nil
          channel.topic_set_at = nil
        else
          channel.topic = topic
          channel.topic_set_by = nickname
          channel.topic_set_at = Time.unix(Time.utc.to_unix)
        end
        Network::NetworkState.set_channel_topic(
          channel_name,
          channel.topic,
          channel.topic_set_by,
          channel.topic_set_at || Time.utc
        )

        topic_message = ":#{client.hostmask || nickname} TOPIC #{channel_name} :#{topic}"
        @notification_service.notify_channel(channel_name, topic_message)
        propagate_to_network(topic_message)

        true
      end

      def query_topic(client : Client, channel_name : String) : Bool
        return false unless nickname = client.nickname
        return false unless Utils::IrcUtils.validate_channel_name(client, channel_name)

        channel = @channel_repository[channel_name]?
        unless channel
          Utils::IrcUtils.send_no_such_channel_error(client, channel_name)
          return false
        end
        if channel.secret? && !channel.has_member?(nickname)
          Utils::IrcUtils.send_no_such_channel_error(client, channel_name)
          return false
        end

        if topic = channel.topic
          client.send_message(Server.clean_name, Numerics::RPL_TOPIC, nickname, channel_name, ":#{topic}")
          if (topic_by = channel.topic_set_by) && (topic_time = channel.topic_set_at)
            client.send_message(Server.clean_name, Numerics::RPL_TOPICTIME, nickname, channel_name, topic_by, topic_time.to_unix.to_s)
          end
        else
          client.send_message(Server.clean_name, Numerics::RPL_NOTOPIC, nickname, channel_name, ":No topic is set")
        end

        true
      end

      # Change channel or user modes with network sync
      def change_mode(client : Client, target : String, mode_string : String, mode_params : Array(String) = [] of String,
                      parameter_index : Int32 = 0) : Bool
        nickname = client.nickname
        return false unless nickname

        if Utils::IrcUtils.valid_channel_name?(target)
          # Channel mode
          change_channel_mode(client, target, mode_string, mode_params, parameter_index)
        else
          # User mode
          change_user_mode(client, target, mode_string)
        end
      end

      def query_mode(client : Client, target : String) : Bool
        nickname = client.nickname
        return false unless nickname

        if Utils::IrcUtils.valid_channel_name?(target)
          query_channel_mode(client, target, nickname)
        else
          query_user_mode(client, target, nickname)
        end
      end

      def oper(client : Client, oper_name : String, password : String) : Bool
        unless client.registered?
          client.send_message(Server.clean_name, Numerics::ERR_NOTREGISTERED, client.nickname || "*", ":You have not registered")
          return false
        end

        nickname = client.nickname
        return false unless nickname

        password_matched = false
        operator_config = nil
        host_masks = nil

        Server.config.operators.each do |operator|
          next unless operator.name == oper_name
          next unless operator.password == password

          password_matched = true
          host_masks ||= oper_host_masks(client)
          if operator.matches?(oper_name, password, host_masks)
            operator_config = operator
            break
          end
        end

        unless password_matched
          client.send_message(Server.clean_name, Numerics::ERR_PASSWDMISMATCH, nickname, ":Password incorrect")
          return false
        end

        unless operator_config
          client.send_message(Server.clean_name, Numerics::ERR_NOOPERHOST, nickname, ":No O-lines for your host")
          return false
        end

        grant_operator_mode(client, nickname, operator_config.mode)
        true
      end

      def kill_user(client : Client, target_nickname : String, reason : String) : Bool
        return false unless require_irc_operator(client)
        return false unless nickname = client.nickname

        if target_nickname.includes?('.')
          client.send_message(Server.clean_name, Numerics::ERR_CANTKILLSERVER, nickname, target_nickname, ":You can't kill a server!")
          return false
        end

        local_user = @user_repository[target_nickname]?
        network_user = Network::NetworkState.get_user(target_nickname)
        unless local_user || network_user
          Utils::IrcUtils.send_no_such_nick_error(client, target_nickname)
          return false
        end
        return false if network_user && !local_user && !require_global_irc_operator(client)

        kill_message = ":#{client.hostmask} KILL #{target_nickname} :#{reason}"
        propagate_to_network(kill_message) if network_user || @user_repository[nickname]?.try(&.global_irc_operator?)
        disconnect_killed_local_user(target_nickname, nickname, reason)
        @channel_repository.remove_user_from_all_channels(target_nickname)
        @user_repository.delete(target_nickname)
        Network::NetworkState.remove_user(target_nickname)
        true
      end

      def line_ban(client : Client, type : String, params : Array(String)) : Bool
        return false unless require_line_privileges(client, type)
        return false unless nickname = client.nickname
        return false if params.empty?

        if params.size == 1
          removed = false
          Utils::IrcUtils.each_list_param(params[0]) do |mask|
            removed = true
            remove_line_ban(client, type, mask)
          end
          return removed
        end

        duration, reason = parse_line_metadata(params)
        reason = "No reason given" if reason.empty?

        added = false
        Utils::IrcUtils.each_list_param(params[0]) do |mask|
          added = true
          add_line_ban(client, type, mask, reason, nickname, duration)
        end
        added
      end

      def rehash(client : Client) : Bool
        return false unless require_irc_operator(client)
        return false unless nickname = client.nickname

        Server.rehash_config!
        client.send_message(Server.clean_name, Numerics::RPL_REHASHING, nickname, Server.name, ":Rehashing")
        true
      rescue ex
        client.send_message(Server.clean_name, Numerics::ERR_UNKNOWNERROR, nickname || "*", "REHASH", ":#{ex.message}")
        false
      end

      def connect_server(client : Client, host : String, port : Int32? = nil, remote_server : String? = nil) : Bool
        return false unless require_irc_operator(client)
        return false unless nickname = client.nickname

        if remote_server && remote_server != Server.name
          return false unless require_global_irc_operator(client)

          if target_server = find_network_server_name(remote_server)
            message = String.build do |io|
              io << "CONNECT " << host
              io << ' ' << port if port
              io << ' ' << target_server
            end
            return true if send_to_server_route(target_server, message)
          end

          client.send_message(Server.clean_name, Numerics::ERR_NOSUCHSERVER, nickname, remote_server, ":No such server")
          return false
        end

        unless Server.connect_linked_server(host, port)
          client.send_message(Server.clean_name, Numerics::RPL_TRYAGAIN, nickname, "CONNECT", ":Please wait a while and try again.")
          return false
        end

        true
      end

      def squit_server(client : Client, server_name : String, comment : String) : Bool
        return false unless require_irc_operator(client)
        return false unless nickname = client.nickname

        if server = find_server_by_name(server_name)
          server.safe_send("SQUIT #{server_name} :#{comment}")
          server.close("Operator SQUIT: #{comment}")
          return true
        end

        return false unless require_global_irc_operator(client)

        if target_server = find_network_server_name(server_name)
          return true if send_to_server_route(target_server, "SQUIT #{target_server} :#{comment}")
        end

        client.send_message(Server.clean_name, Numerics::ERR_NOSUCHSERVER, nickname, server_name, ":No such server")
        false
      end

      def die(client : Client, reason : String) : Bool
        return false unless require_irc_operator(client)
        return false unless nickname = client.nickname

        unless Server.config.allow_die?
          client.send_message(Server.clean_name, Numerics::ERR_NOPRIVILEGES, nickname, ":DIE is disabled in server configuration")
          return false
        end

        spawn { Server.shutdown_by_operator(reason) }
        true
      end

      def restart(client : Client, reason : String) : Bool
        return false unless require_irc_operator(client)
        return false unless nickname = client.nickname

        unless Server.config.allow_restart?
          client.send_message(Server.clean_name, Numerics::ERR_NOPRIVILEGES, nickname, ":RESTART is disabled in server configuration")
          return false
        end

        spawn { Server.restart_by_operator(reason) }
        true
      end

      private def query_channel_mode(client : Client, channel_name : String, nickname : String) : Bool
        channel = @channel_repository[channel_name]?
        unless channel
          Utils::IrcUtils.send_no_such_channel_error(client, channel_name)
          return false
        end

        modes, params = build_channel_mode_query(channel, channel.has_member?(nickname))
        client.send_message(String.build do |io|
          io << Server.clean_name << ' ' << Numerics::RPL_CHANNELMODEIS << ' ' << nickname << ' ' << channel.name << ' ' << modes
          params.each do |param|
            io << ' ' << param
          end
        end)
        client.send_message(
          Server.clean_name,
          Numerics::RPL_CREATIONTIME,
          nickname,
          channel.name,
          channel.created_at.to_unix.to_s
        )
        true
      end

      private def query_user_mode(client : Client, target : String, nickname : String) : Bool
        unless Domain::CaseMapping.same?(target, nickname)
          Utils::IrcUtils.send_users_dont_match_error(client)
          return false
        end

        user = @user_repository[nickname]?
        unless user
          Utils::IrcUtils.send_no_such_nick_error(client, target)
          return false
        end

        client.send_message(
          Server.clean_name,
          Numerics::RPL_UMODEIS,
          nickname,
          ":#{Utils::IrcUtils.mode_string(user.modes)}"
        )
        true
      end

      private def build_channel_mode_query(channel : Domain::Channel, include_sensitive_params : Bool) : Tuple(String, Array(String))
        params = [] of String
        modes = String.build do |io|
          io << '+'
          CHANNEL_MODE_ORDER.each do |mode_char|
            next unless channel.modes.includes?(mode_char)

            case mode_char
            when 'k'
              next unless password = channel.password
              params << password if include_sensitive_params
            when 'l'
              next unless limit = channel.user_limit
              params << limit.to_s if include_sensitive_params
            when 'b'
              next if channel.ban_list.empty?
            end

            io << mode_char
          end
        end

        {modes, params}
      end

      private def change_channel_mode(client : Client, channel_name : String, mode_string : String,
                                      mode_params : Array(String), parameter_index : Int32) : Bool
        return false unless nickname = client.nickname
        return false unless channel = validate_channel_operator(client, channel_name, nickname)

        return false if mode_string.size < 2

        result = channel.apply_modes(mode_string, mode_params, parameter_index)
        applied_modes = result[:modes]
        parameter_count = result[:parameter_count]

        return false if applied_modes.empty?

        Network::NetworkState.sync_channel(channel)

        targets = mode_params.each.skip(parameter_index).first(parameter_count)
        mode_message = String.build do |io|
          io << ':' << (client.hostmask || "") << " MODE " << channel_name << ' ' << applied_modes
          targets.each do |parameter|
            io << ' ' << parameter
          end
        end
        @notification_service.notify_channel(channel_name, mode_message)
        propagate_to_network(mode_message)

        true
      end

      private def change_user_mode(client : Client, target : String, mode_string : String) : Bool
        return false unless nickname = client.nickname

        # Only allow users to change their own modes
        unless Domain::CaseMapping.same?(target, nickname)
          Utils::IrcUtils.send_users_dont_match_error(client)
          return false
        end

        user = @user_repository[nickname]?
        unless user
          Utils::IrcUtils.send_no_such_nick_error(client, target)
          return false
        end

        # Parse mode string
        return false if mode_string.size < 2

        applied_modes = apply_user_mode_string(user, mode_string)

        # Send mode change notification to user
        client.send_message(
          Server.clean_name,
          Numerics::RPL_UMODEIS,
          nickname,
          ":#{Utils::IrcUtils.mode_string(user.modes)}"
        )

        # Propagate to network
        propagate_to_network(":#{client.hostmask} MODE #{nickname} #{applied_modes}") unless applied_modes.empty?

        true
      end

      private def apply_user_mode_string(user : Domain::User, mode_string : String) : String
        adding = true
        last_sign = '\0'

        String.build do |io|
          mode_string.each_char do |mode_char|
            case mode_char
            when '+'
              adding = true
            when '-'
              adding = false
            else
              next unless apply_user_mode(user, mode_char, adding)

              sign = adding ? '+' : '-'
              if sign != last_sign
                io << sign
                last_sign = sign
              end
              io << mode_char
            end
          end
        end
      end

      private def apply_user_mode(user : Domain::User, mode_char : Char, adding : Bool) : Bool
        if SELF_USER_MODES.includes?(mode_char)
          adding ? user.modes << mode_char : user.modes.delete(mode_char)
          true
        elsif Domain::User::OPERATOR_MODES.includes?(mode_char) && !adding
          user.modes.delete(mode_char)
          true
        else
          false
        end
      end

      private def grant_operator_mode(client : Client, nickname : String, mode : Char)
        return unless user = @user_repository[nickname]?

        mode_string = operator_mode_change(user.modes, mode)
        remove_operator_modes(user.modes)
        user.modes << mode
        if network_user = Network::NetworkState.get_user(nickname)
          remove_operator_modes(network_user.modes)
          network_user.modes << mode
        end

        client.send_message(Server.clean_name, Numerics::RPL_YOUREOPER, nickname, ":You are now an IRC operator")
        client.send_message(Server.clean_name, "MODE", nickname, mode_string)
        propagate_to_network(":#{client.hostmask} MODE #{nickname} #{mode_string}")
      end

      private def operator_mode_change(current_modes : Set(Char), new_mode : Char) : String
        String.build do |io|
          removing_modes = false
          current_modes.each do |mode|
            next unless Domain::User::OPERATOR_MODES.includes?(mode) && mode != new_mode

            unless removing_modes
              io << '-'
              removing_modes = true
            end
            io << mode
          end

          io << '+' << new_mode
        end
      end

      private def remove_operator_modes(modes : Set(Char)) : Nil
        Domain::User::OPERATOR_MODES.each do |mode|
          modes.delete(mode)
        end
      end

      private def oper_host_masks(client : Client) : Array(String)
        masks = [] of String
        if hostmask = client.hostmask
          masks << hostmask
        end
        masks << client.hostname
        if host = client.host
          masks << host
          if host.includes?(':')
            masks << host.rpartition(':')[0]
          end
        end
        masks
      end

      private def require_irc_operator(client : Client) : Bool
        return false unless nickname = client.nickname
        return true if @user_repository[nickname]?.try(&.irc_operator?)

        client.send_message(Server.clean_name, Numerics::ERR_NOPRIVILEGES, nickname, ":Permission Denied- You're not an IRC operator")
        false
      end

      private def require_global_irc_operator(client : Client) : Bool
        return false unless nickname = client.nickname
        return true if @user_repository[nickname]?.try(&.global_irc_operator?)

        client.send_message(Server.clean_name, Numerics::ERR_NOPRIVILEGES, nickname, ":Permission Denied- You're not a global IRC operator")
        false
      end

      private def require_line_privileges(client : Client, type : String) : Bool
        type.upcase == Domain::LineBan::GLINE ? require_global_irc_operator(client) : require_irc_operator(client)
      end

      private def add_line_ban(client : Client, type : String, mask : String, reason : String, set_by : String, duration : Time::Span?) : Nil
        line = Network::LineState.add(type, mask, reason, set_by, duration)
        return unless line

        client.send_message(Server.clean_name, "NOTICE", client.nickname || "*", ":*** #{line.type} added for #{line.mask}")
        Network::LineState.enforce(line)
        propagate_to_network(line.server_message) if line.type == Domain::LineBan::GLINE
      end

      private def remove_line_ban(client : Client, type : String, mask : String) : Nil
        normalized_type = type.upcase
        normalized_mask = Network::LineState.normalize_mask(normalized_type, mask)

        if Network::LineState.remove(normalized_type, normalized_mask)
          client.send_message(Server.clean_name, "NOTICE", client.nickname || "*", ":*** #{normalized_type} removed for #{normalized_mask}")
          propagate_to_network("#{normalized_type} #{normalized_mask}") if normalized_type == Domain::LineBan::GLINE
        else
          client.send_message(Server.clean_name, "NOTICE", client.nickname || "*", ":*** #{normalized_type} not found for #{normalized_mask}")
        end
      end

      private def parse_line_metadata(params : Array(String)) : Tuple(Time::Span?, String)
        valid_duration, duration = parse_duration(params[1])
        reason_start = valid_duration ? 2 : 1

        {duration, Utils::IrcUtils.trailing_param(params, reason_start)}
      end

      private def parse_duration(token : String) : Tuple(Bool, Time::Span?)
        return {true, nil} if token == "0"
        return {true, token.to_i64.seconds} if token.matches?(/^\d+$/)

        parse_compound_duration(token)
      end

      private def parse_compound_duration(token : String) : Tuple(Bool, Time::Span?)
        total = 0_i64
        number = 0_i64
        saw_number = false
        token.each_char do |char|
          if char >= '0' && char <= '9'
            number = number * 10 + (char.ord - '0'.ord)
            saw_number = true
            next
          end

          return {false, nil} unless saw_number

          multiplier = duration_unit_seconds(char)
          return {false, nil} unless multiplier

          total += number * multiplier

          number = 0_i64
          saw_number = false
        end

        return {false, nil} if saw_number || total <= 0

        {true, total.seconds}
      end

      private def duration_unit_seconds(char : Char) : Int64?
        case char.downcase
        when 'y'
          365_i64 * 24 * 60 * 60
        when 'w'
          7_i64 * 24 * 60 * 60
        when 'd'
          24_i64 * 60 * 60
        when 'h'
          60_i64 * 60
        when 'm'
          60_i64
        when 's'
          1_i64
        end
      end

      private def find_server_by_name(server_name : String) : LinkServer?
        ServerHandler.servers.find do |server|
          server.name == server_name ||
            server.target_host == server_name ||
            "#{server.target_host}:#{server.target_port}" == server_name
        end
      end

      private def find_network_server_name(server_mask : String) : String?
        return Server.name if server_mask == Server.name
        if server = find_server_by_name(server_mask)
          return server.name
        end
        return server_mask if Network::NetworkState.get_server(server_mask)

        Network::NetworkState.server_list(server_mask).first?.try(&.name)
      end

      private def send_to_server_route(target_server : String, message : String) : LinkServer?
        server = find_server_by_name(target_server)
        unless server
          if route_to_server = Network::NetworkState.route_to_server(target_server)
            server = find_server_by_name(route_to_server)
          end
        end
        return unless server

        server.safe_send(message) ? server : nil
      end

      private def disconnect_killed_local_user(target_nickname : String, oper_nickname : String, reason : String) : Nil
        return unless target_client = @user_repository.get_client(target_nickname)

        target_client.send_error("Killed by #{oper_nickname}: #{reason}")
        target_client.close
      rescue ClosedClient
      end

      def kick_user(client : Client, channel_name : String, target_nickname : String, reason : String? = nil) : Bool
        return false unless nickname = client.nickname
        return false unless channel = validate_channel_operator(client, channel_name, nickname)

        unless channel.has_member?(target_nickname)
          client.send_message(Server.clean_name, Numerics::ERR_USERNOTINCHANNEL, nickname, target_nickname, channel_name, ":They aren't on that channel")
          return false
        end

        kick_message = String.build do |io|
          io << ':' << (client.hostmask || nickname) << " KICK " << channel_name << ' ' << target_nickname
          io << " :" << reason if reason
        end
        if kicked_user_client = @user_repository.get_client(target_nickname)
          kicked_user_client.send_message(kick_message)
        end

        @channel_repository.part_user(channel.name, target_nickname)
        @notification_service.notify_channel(channel_name, kick_message)
        propagate_to_network(kick_message)

        true
      end

      # Sync new user with network state
      def sync_new_user(client : Client) : Bool
        return false unless nickname = client.nickname

        if user = @user_repository[nickname]?
          Network::NetworkState.add_user(
            nickname,
            user.username,
            user.hostname,
            user.realname,
            user.server
          )
          propagate_user_to_network(nickname, user)
          true
        else
          false
        end
      end

      private def validate_join_permissions(client : Client, channel : Domain::Channel, password : String?) : Bool
        return false unless nickname = client.nickname

        # Invite only?
        if channel.invite_only? && !channel.invited?(nickname)
          Utils::IrcUtils.send_invite_only_error(client, channel.name)
          return false
        end

        # Channel key/password?
        unless channel.password_matches?(password)
          Utils::IrcUtils.send_bad_channel_key_error(client, channel.name)
          return false
        end

        # User limit check
        if channel.full?
          Utils::IrcUtils.send_channel_full_error(client, channel.name)
          return false
        end

        # Ban checking
        if ban_context = client.ban_match_context
          if channel.banned?(ban_context)
            Utils::IrcUtils.send_banned_from_channel_error(client, channel.name)
            return false
          end
        end

        true
      end

      private def validate_channel_operator(client : Client, channel_name : String, nickname : String) : Domain::Channel?
        return nil unless Utils::IrcUtils.validate_channel_name(client, channel_name)

        channel = @channel_repository[channel_name]?
        unless channel
          Utils::IrcUtils.send_no_such_channel_error(client, channel_name)
          return nil
        end

        unless channel.has_member?(nickname)
          Utils::IrcUtils.send_not_on_channel_error(client, channel_name)
          return nil
        end

        unless Utils::IrcUtils.user_is_operator?(channel, nickname)
          Utils::IrcUtils.send_not_operator_error(client, channel_name)
          return nil
        end

        channel
      end

      private def validate_topic_change(client : Client, channel_name : String, nickname : String) : Domain::Channel?
        return nil unless Utils::IrcUtils.validate_channel_name(client, channel_name)

        channel = @channel_repository[channel_name]?
        unless channel
          Utils::IrcUtils.send_no_such_channel_error(client, channel_name)
          return nil
        end

        unless channel.has_member?(nickname)
          Utils::IrcUtils.send_not_on_channel_error(client, channel_name)
          return nil
        end

        if channel.has_mode?('t') && !Utils::IrcUtils.user_is_operator?(channel, nickname)
          Utils::IrcUtils.send_not_operator_error(client, channel_name)
          return nil
        end

        channel
      end

      private def sync_nick_with_network(old_nickname : String, new_nickname : String)
        # Remove old user and add new one
        if user_info = Network::NetworkState.get_user(old_nickname)
          Network::NetworkState.remove_user(old_nickname)
          Network::NetworkState.add_user(
            new_nickname,
            user_info.username,
            user_info.hostname,
            user_info.realname,
            user_info.server
          )
        end
      end

      # Network propagation methods
      private def propagate_to_network(message : String)
        ServerHandler.servers.each do |link_server|
          link_server.safe_send(message)
        end
      end

      private def build_part_message(client : Client, channel_name : String, reason : String? = nil) : String
        String.build do |io|
          io << ':' << client.hostmask << " PART " << channel_name
          io << " :" << reason if reason
        end
      end

      private def propagate_user_to_network(nickname : String, user : Domain::User)
        modes = Utils::IrcUtils.mode_string(user.modes)
        connected_at = Network::NetworkState.get_user(nickname).try(&.connected_at) || Time.utc
        message = String.build do |io|
          io << "NICK " << nickname << " 1 " << connected_at.to_unix << ' '
          io << user.username << ' ' << user.hostname << ' '
          io << Server.name << ' ' << modes << " :" << user.realname
        end

        propagate_to_network(message)
      end

      private def route_channel_message(sender : Client, channel_name : String, message : String) : Bool
        return false unless sender_nick = sender.nickname
        unless channel = @channel_repository[channel_name]?
          Utils::IrcUtils.send_cannot_send_to_channel_error(sender, channel_name)
          return false
        end
        return false unless can_send_to_channel?(sender, channel, send_errors: true)

        wire_message = ":#{sender.hostmask || sender_nick} PRIVMSG #{channel_name} :#{message}"
        @notification_service.notify_channel(channel_name, wire_message, sender_nick)
        propagate_to_network(wire_message)

        true
      end

      private def route_private_message(sender : Client, target : String, message : String) : Bool
        return false unless sender_nick = sender.nickname

        if @user_repository.has_client?(target)
          send_away_reply(sender, sender_nick, target)
          @notification_service.notify_user(target, ":#{sender.hostmask || sender_nick} PRIVMSG #{target} :#{message}")
          true
        else
          route_remote_user_message(sender, target, "PRIVMSG", message, send_errors: true)
        end
      end

      private def route_channel_notice(sender : Client, channel_name : String, message : String) : Bool
        return false unless sender_nick = sender.nickname
        return false unless channel = @channel_repository[channel_name]?
        return false unless can_send_to_channel?(sender, channel, send_errors: false)

        wire_message = ":#{sender.hostmask || sender_nick} NOTICE #{channel_name} :#{message}"
        @notification_service.notify_channel(channel_name, wire_message, sender_nick)
        propagate_to_network(wire_message)

        true
      end

      private def can_send_to_channel?(sender : Client, channel : Domain::Channel, send_errors : Bool) : Bool
        return false unless nickname = sender.nickname

        member_modes = channel.member_modes?(nickname)
        privileged = member_modes.try(&.any? { |mode| Domain::Channel::USER_MODES.includes?(mode) }) || false
        blocked = channel.has_mode?('n') && member_modes.nil? ||
                  channel.has_mode?('m') && !privileged ||
                  !privileged && sender.ban_match_context.try { |context| channel.banned?(context) }
        return true unless blocked

        Utils::IrcUtils.send_cannot_send_to_channel_error(sender, channel.name) if send_errors
        false
      end

      private def route_private_notice(sender : Client, target : String, message : String) : Bool
        return false unless sender_nick = sender.nickname

        if @user_repository.has_client?(target)
          @notification_service.notify_user(target, ":#{sender.hostmask || sender_nick} NOTICE #{target} :#{message}")
          true
        else
          route_remote_user_message(sender, target, "NOTICE", message, send_errors: false)
        end
      end

      private def send_away_reply(sender : Client, sender_nick : String, target : String)
        return unless target_user = @user_repository[target]?
        return unless away_message = target_user.away_message

        sender.send_message(
          Server.clean_name,
          Numerics::RPL_AWAY,
          sender_nick,
          target,
          ":#{away_message}"
        )
      end

      private def route_remote_user_message(sender : Client, target : String, command : String, message : String, send_errors : Bool) : Bool
        target_server = Network::NetworkState.get_user(target).try(&.server)
        unless target_server
          Utils::IrcUtils.send_no_such_nick_error(sender, target) if send_errors
          return false
        end

        server = find_server_for_route(target_server)
        unless server && server.safe_send(":#{sender.hostmask} #{command} #{target} :#{message}")
          Utils::IrcUtils.send_no_such_nick_error(sender, target) if send_errors
          return false
        end

        true
      end

      private def find_server_for_route(target_server : String) : LinkServer?
        route_to_server = Network::NetworkState.route_to_server(target_server)
        if route_to_server
          ServerHandler.servers.find { |server_handler| server_handler.name == route_to_server }
        elsif !ServerHandler.servers.empty?
          ServerHandler.servers.first
        end
      end

      def send_names_reply(client : Client, channel : Domain::Channel) : Nil
        return unless nickname = client.nickname

        Log.debug { "Channel #{channel.name} members: #{channel.members.each_key.join(", ")}" }

        channel_type = channel.secret? ? "@" : channel.private? ? "*" : "="
        requester_is_member = channel.has_member?(nickname)
        names_line = IO::Memory.new
        names_in_chunk = 0
        channel.members.each do |member_nick, modes|
          if member_nick.empty?
            Log.warn { "Found empty nickname in channel #{channel.name}" }
            next
          end
          next if @user_repository[member_nick]?.try(&.modes.includes?('i')) && !requester_is_member

          names_line << ' ' unless names_in_chunk == 0
          if prefix = Domain::Channel.member_prefix(modes)
            names_line << prefix
          end
          names_line << member_nick
          names_in_chunk += 1

          if names_in_chunk == 10
            send_names_chunk(client, nickname, channel_type, channel.name, names_line)
            names_line.clear
            names_in_chunk = 0
          end
        end

        send_names_chunk(client, nickname, channel_type, channel.name, names_line) if names_in_chunk > 0
      end

      private def send_names_chunk(client : Client, nickname : String, channel_type : String,
                                   channel_name : String, names_line : IO::Memory) : Nil
        client.send_message(Server.clean_name, Numerics::RPL_NAMREPLY, nickname, channel_type, channel_name, ":#{names_line}")
      end
    end
  end
end
