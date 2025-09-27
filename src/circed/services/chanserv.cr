require "./base_service"
require "./database"
require "./models"

module Circed::Services
  # ChanServ - Channel registration and management service
  class ChanServ < BaseService
    def initialize
      super("ChanServ", "services", Server.config.host, "Channel Registration Service")
    end

    def handle_message(sender : String, command : String, params : Array(String))
      cmd = command.upcase

      # Channel management commands
      if handle_channel_commands(sender, cmd, params)
        return
      end

      # User management commands
      if handle_user_commands(sender, cmd, params)
        return
      end

      # Information commands
      if handle_info_commands(sender, cmd, params)
        return
      end

      send_notice(sender, "Unknown command. Type /msg ChanServ HELP for available commands.")
    end

    private def handle_channel_commands(sender : String, cmd : String, params : Array(String)) : Bool
      case cmd
      when "REGISTER"
        handle_register(sender, params)
        true
      when "DROP"
        handle_drop(sender, params)
        true
      when "ACCESS"
        handle_access(sender, params)
        true
      when "TOPIC"
        handle_topic(sender, params)
        true
      else
        false
      end
    end

    private def handle_user_commands(sender : String, cmd : String, params : Array(String)) : Bool
      case cmd
      when "IDENTIFY"
        handle_identify(sender, params)
        true
      when "OP"
        handle_op(sender, params)
        true
      when "DEOP"
        handle_deop(sender, params)
        true
      when "VOICE"
        handle_voice(sender, params)
        true
      when "DEVOICE"
        handle_devoice(sender, params)
        true
      else
        false
      end
    end

    private def handle_info_commands(sender : String, cmd : String, params : Array(String)) : Bool
      case cmd
      when "INFO"
        handle_info(sender, params)
        true
      when "HELP"
        handle_help(sender, params)
        true
      else
        false
      end
    end

    private def handle_register(sender : String, params : Array(String))
      if params.size < 2
        send_notice(sender, "Syntax: REGISTER <#channel> <password>")
        return
      end

      channel_name = params[0]

      unless channel_name.starts_with?('#')
        send_notice(sender, "Channel name must start with #")
        return
      end

      # Check if user is in the channel and has ops
      channel = Network::NetworkState.get_channel(channel_name)
      unless channel
        send_notice(sender, "You must be in the channel to register it.")
        return
      end

      unless channel.members[sender]?.try(&.includes?('o'))
        send_notice(sender, "You must have operator status in the channel to register it.")
        return
      end

      # Check if channel is already registered
      if get_registered_channel(channel_name)
        send_notice(sender, "Channel #{channel_name} is already registered.")
        return
      end

      # Register the channel
      Database.db.exec(
        "INSERT INTO registered_channels (channel_name, founder, topic, modes) VALUES (?, ?, ?, ?)",
        channel_name, sender, channel.topic, "+nt"
      )

      # Add founder access
      Database.db.exec(
        "INSERT INTO channel_access (channel_name, nickname, access_level, added_by) VALUES (?, ?, ?, ?)",
        channel_name, sender, AccessLevel::Founder.value, "ChanServ"
      )

      send_notice(sender, "Channel #{channel_name} has been registered successfully.")
      send_notice(sender, "Your founder access has been granted.")
    end

    private def handle_drop(sender : String, params : Array(String))
      if params.size < 1
        send_notice(sender, "Syntax: DROP <#channel>")
        return
      end

      channel_name = params[0]
      registered_channel = get_registered_channel(channel_name)

      unless registered_channel
        send_notice(sender, "Channel #{channel_name} is not registered.")
        return
      end

      unless registered_channel.founder.downcase == sender.downcase
        send_notice(sender, "You are not the founder of #{channel_name}.")
        return
      end

      # Remove channel and all access entries
      Database.db.exec("DELETE FROM registered_channels WHERE channel_name = ?", channel_name)
      Database.db.exec("DELETE FROM channel_access WHERE channel_name = ?", channel_name)

      send_notice(sender, "Channel #{channel_name} has been dropped.")
    end

    private def handle_identify(sender : String, params : Array(String))
      if params.size < 2
        send_notice(sender, "Syntax: IDENTIFY <#channel> <password>")
        return
      end

      channel_name = params[0]

      registered_channel = get_registered_channel(channel_name)
      unless registered_channel
        send_notice(sender, "Channel #{channel_name} is not registered.")
        return
      end

      # For simplicity, we'll use the founder check
      # In a real implementation, you'd have proper password verification
      unless registered_channel.founder.downcase == sender.downcase
        send_notice(sender, "Invalid password for #{channel_name}.")
        return
      end

      send_notice(sender, "You are now identified for #{channel_name}.")

      # Grant appropriate channel modes if user is in channel
      if channel = Network::NetworkState.get_channel(channel_name)
        if channel.members[sender]?
          access_level = registered_channel.get_access_level(sender)
          apply_access_modes(channel_name, sender, access_level)
        end
      end
    end

    private def handle_access(sender : String, params : Array(String))
      if params.size < 2
        send_notice(sender, "Syntax: ACCESS <#channel> <ADD|DEL|LIST> [nickname] [level]")
        return
      end

      channel_name = params[0]
      action = params[1].upcase

      registered_channel = get_registered_channel(channel_name)
      unless registered_channel
        send_notice(sender, "Channel #{channel_name} is not registered.")
        return
      end

      # Check if sender has access to modify access list
      sender_access = registered_channel.get_access_level(sender)
      unless sender_access >= AccessLevel::Admin
        send_notice(sender, "You need admin access or higher to modify the access list.")
        return
      end

      execute_access_action(sender, channel_name, action, params)
    end

    private def handle_op(sender : String, params : Array(String))
      if params.size < 2
        send_notice(sender, "Syntax: OP <#channel> <nickname>")
        return
      end

      channel_name = params[0]
      target = params[1]

      registered_channel = get_registered_channel(channel_name)
      unless registered_channel
        send_notice(sender, "Channel #{channel_name} is not registered.")
        return
      end

      # Check sender access
      sender_access = registered_channel.get_access_level(sender)
      unless sender_access >= AccessLevel::Operator
        send_notice(sender, "You need operator access or higher.")
        return
      end

      # Check target access
      target_access = registered_channel.get_access_level(target)
      unless target_access >= AccessLevel::Operator
        send_notice(sender, "#{target} does not have operator access in #{channel_name}.")
        return
      end

      # Apply op mode
      apply_channel_mode(channel_name, "+o", target)
      send_notice(sender, "#{target} has been given operator status in #{channel_name}.")
    end

    private def handle_deop(sender : String, params : Array(String))
      if params.size < 2
        send_notice(sender, "Syntax: DEOP <#channel> <nickname>")
        return
      end

      channel_name = params[0]
      target = params[1]

      registered_channel = get_registered_channel(channel_name)
      unless registered_channel
        send_notice(sender, "Channel #{channel_name} is not registered.")
        return
      end

      # Check sender access
      sender_access = registered_channel.get_access_level(sender)
      unless sender_access >= AccessLevel::Admin
        send_notice(sender, "You need admin access or higher.")
        return
      end

      # Apply deop mode
      apply_channel_mode(channel_name, "-o", target)
      send_notice(sender, "#{target} has been removed operator status in #{channel_name}.")
    end

    private def handle_voice(sender : String, params : Array(String))
      if params.size < 2
        send_notice(sender, "Syntax: VOICE <#channel> <nickname>")
        return
      end

      channel_name = params[0]
      target = params[1]

      registered_channel = get_registered_channel(channel_name)
      unless registered_channel
        send_notice(sender, "Channel #{channel_name} is not registered.")
        return
      end

      # Check sender access
      sender_access = registered_channel.get_access_level(sender)
      unless sender_access >= AccessLevel::Operator
        send_notice(sender, "You need operator access or higher.")
        return
      end

      # Check target access
      target_access = registered_channel.get_access_level(target)
      unless target_access >= AccessLevel::Voice
        send_notice(sender, "#{target} does not have voice access in #{channel_name}.")
        return
      end

      # Apply voice mode
      apply_channel_mode(channel_name, "+v", target)
      send_notice(sender, "#{target} has been given voice in #{channel_name}.")
    end

    private def handle_devoice(sender : String, params : Array(String))
      if params.size < 2
        send_notice(sender, "Syntax: DEVOICE <#channel> <nickname>")
        return
      end

      channel_name = params[0]
      target = params[1]

      registered_channel = get_registered_channel(channel_name)
      unless registered_channel
        send_notice(sender, "Channel #{channel_name} is not registered.")
        return
      end

      # Check sender access
      sender_access = registered_channel.get_access_level(sender)
      unless sender_access >= AccessLevel::Operator
        send_notice(sender, "You need operator access or higher.")
        return
      end

      # Apply devoice mode
      apply_channel_mode(channel_name, "-v", target)
      send_notice(sender, "#{target} has been removed voice in #{channel_name}.")
    end

    private def handle_topic(sender : String, params : Array(String))
      if params.size < 2
        send_notice(sender, "Syntax: TOPIC <#channel> <topic>")
        return
      end

      channel_name = params[0]
      topic = params[1..-1].join(" ")

      registered_channel = get_registered_channel(channel_name)
      unless registered_channel
        send_notice(sender, "Channel #{channel_name} is not registered.")
        return
      end

      # Check sender access
      sender_access = registered_channel.get_access_level(sender)
      unless sender_access >= AccessLevel::Operator
        send_notice(sender, "You need operator access or higher.")
        return
      end

      # Update topic in database
      Database.db.exec("UPDATE registered_channels SET topic = ? WHERE channel_name = ?", topic, channel_name)

      # Set topic in channel if it exists
      if channel = Network::NetworkState.get_channel(channel_name)
        channel.topic = topic
        # Broadcast topic change to all channel members
        channel.members.each_key do |member|
          if user = get_user(member)
            user.send_message(":ChanServ!services@#{Server.config.host} TOPIC #{channel_name} :#{topic}")
          end
        end
      end

      send_notice(sender, "Topic for #{channel_name} has been changed.")
    end

    private def handle_info(sender : String, params : Array(String))
      if params.size < 1
        send_notice(sender, "Syntax: INFO <#channel>")
        return
      end

      channel_name = params[0]
      registered_channel = get_registered_channel(channel_name)

      unless registered_channel
        send_notice(sender, "Channel #{channel_name} is not registered.")
        return
      end

      send_notice(sender, "Information for #{channel_name}:")
      send_notice(sender, "  Founder: #{registered_channel.founder}")
      send_notice(sender, "  Registered: #{registered_channel.registered_at}")
      send_notice(sender, "  Last used: #{registered_channel.last_used}")
      if topic = registered_channel.topic
        send_notice(sender, "  Topic: #{topic}")
      end
      send_notice(sender, "  Modes: #{registered_channel.modes}")
    end

    private def handle_help(sender : String, params : Array(String))
      send_notice(sender, "ChanServ commands:")
      send_notice(sender, "  REGISTER <#channel> <password> - Register a channel")
      send_notice(sender, "  DROP <#channel> - Drop a registered channel")
      send_notice(sender, "  IDENTIFY <#channel> <password> - Identify for a channel")
      send_notice(sender, "  ACCESS <#channel> <ADD|DEL|LIST> [nick] [level] - Manage access list")
      send_notice(sender, "  OP <#channel> <nickname> - Grant operator status")
      send_notice(sender, "  DEOP <#channel> <nickname> - Remove operator status")
      send_notice(sender, "  VOICE <#channel> <nickname> - Grant voice")
      send_notice(sender, "  DEVOICE <#channel> <nickname> - Remove voice")
      send_notice(sender, "  TOPIC <#channel> <topic> - Set channel topic")
      send_notice(sender, "  INFO <#channel> - Show channel information")
      send_notice(sender, "Access levels: 1=Voice, 3=Operator, 4=Admin, 5=Founder")
    end

    def get_registered_channel(channel_name : String) : RegisteredChannel?
      Database.db.query_one?(
        "SELECT id, channel_name, founder, registered_at, topic, modes, last_used FROM registered_channels WHERE channel_name = ?",
        channel_name
      ) do |result_set|
        access_list = Database.db.query_all(
          "SELECT id, channel_name, nickname, access_level, added_by, added_at FROM channel_access WHERE channel_name = ?",
          channel_name
        ) do |access_result_set|
          ChannelAccess.new(
            access_result_set.read(Int32), access_result_set.read(String), access_result_set.read(String),
            access_result_set.read(Int32), access_result_set.read(String), access_result_set.read(Time)
          )
        end

        RegisteredChannel.new(
          result_set.read(Int32), result_set.read(String), result_set.read(String),
          result_set.read(Time), result_set.read(String?), result_set.read(String),
          access_list.to_json, result_set.read(Time)
        )
      end
    end

    private def list_access(sender : String, channel_name : String)
      access_list = Database.db.query_all(
        "SELECT nickname, access_level, added_by FROM channel_access WHERE channel_name = ? ORDER BY access_level DESC",
        channel_name
      ) do |result_set|
        {result_set.read(String), AccessLevel.from_value(result_set.read(Int32)), result_set.read(String)}
      end

      if access_list.empty?
        send_notice(sender, "Access list for #{channel_name} is empty.")
        return
      end

      send_notice(sender, "Access list for #{channel_name}:")
      access_list.each do |(nickname, level, added_by)|
        send_notice(sender, "  #{nickname} (Level #{level.value}) - added by #{added_by}")
      end
    end

    private def add_access(sender : String, channel_name : String, nickname : String, level_str : String)
      level = level_str.to_i32?
      unless level && level >= 1 && level <= 5
        send_notice(sender, "Invalid access level. Use 1-5 (1=Voice, 3=Operator, 4=Admin, 5=Founder)")
        return
      end

      access_level = AccessLevel.from_value(level)

      Database.db.exec(
        "INSERT OR REPLACE INTO channel_access (channel_name, nickname, access_level, added_by) VALUES (?, ?, ?, ?)",
        channel_name, nickname, access_level.value, sender
      )

      send_notice(sender, "#{nickname} has been granted level #{level} access in #{channel_name}.")
    end

    private def del_access(sender : String, channel_name : String, nickname : String)
      Database.db.exec(
        "DELETE FROM channel_access WHERE channel_name = ? AND nickname = ?",
        channel_name, nickname
      )

      send_notice(sender, "#{nickname} has been removed from the access list of #{channel_name}.")
    end

    private def apply_access_modes(channel_name : String, nickname : String, access_level : AccessLevel)
      case access_level
      when .founder?, .admin?
        apply_channel_mode(channel_name, "+o", nickname)
      when .operator?
        apply_channel_mode(channel_name, "+o", nickname)
      when .voice?
        apply_channel_mode(channel_name, "+v", nickname)
      end
    end

    private def apply_channel_mode(channel_name : String, mode : String, target : String)
      if channel = Network::NetworkState.get_channel(channel_name)
        # Broadcast mode change to all channel members
        channel.members.each_key do |member|
          if user = get_user(member)
            user.send_message(":ChanServ!services@#{Server.config.host} MODE #{channel_name} #{mode} #{target}")
          end
        end

        # Apply mode change to channel state
        if mode.starts_with?('+')
          mode_char = mode[1]
          if current_modes = channel.members[target]?
            unless current_modes.includes?(mode_char)
              current_modes.add(mode_char)
            end
          end
        elsif mode.starts_with?('-')
          mode_char = mode[1]
          if current_modes = channel.members[target]?
            current_modes.delete(mode_char)
          end
        end
      end
    end

    private def execute_access_action(sender : String, channel_name : String, action : String, params : Array(String))
      case action
      when "LIST"
        list_access(sender, channel_name)
      when "ADD"
        if params.size < 4
          send_notice(sender, "Syntax: ACCESS <#channel> ADD <nickname> <level>")
          return
        end
        add_access(sender, channel_name, params[2], params[3])
      when "DEL"
        if params.size < 3
          send_notice(sender, "Syntax: ACCESS <#channel> DEL <nickname>")
          return
        end
        del_access(sender, channel_name, params[2])
      else
        send_notice(sender, "Invalid access command. Use ADD, DEL, or LIST.")
      end
    end
  end
end
