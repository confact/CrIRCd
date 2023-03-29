module Circed
  class Channel
    getter name : String

    property topic : String = ""
    property topic_setter : ChannelUser? = nil
    property topic_set_at : Time? = nil

    getter bans : Array(String) = [] of String

    getter modes : Hash(String, String?) = {} of String => String?

    getter users : Array(ChannelUser) = [] of ChannelUser

    def initialize(name)
      if name.starts_with?("#")
        @name = name
      else
        @name = "#" + name
      end
    end

    def add_client(user : Client, key : String? = nil)
      if is_banned?(user)
        user.send_message(Server.clean_name, Numerics::ERR_BANNEDFROMCHAN, irc_name, ":You are banned from #{@name}")
        return
      end

      if has_mode?("k") && (key.nil? || key != get_mode_param("k"))
        user.send_message(Server.clean_name, Numerics::ERR_BADCHANNELKEY, irc_name, ":Cannot join channel (Incorrect channel key)")
        return
      end

      if user_in_channel?(user)
        user.send_message(Server.clean_name, Numerics::ERR_USERONCHANNEL, ":You are already on #{@name}")
        return
      end
      channel_user = ChannelUser.new(user, self)
      if @users.empty?
        channel_user.add_mode("o")
      end
      @users << channel_user
      @users.each do |u|
        u.send_message_to_server("JOIN", user.nickname.to_s, user.user.try(&.name), user.host, [name])
      end
      if @topic.empty?
        user.send_message(Server.clean_name, Numerics::RPL_NOTOPIC, user.nickname.to_s, name, ":No topic is set")
      else
        user.send_message(Server.clean_name, Numerics::RPL_TOPIC, user.nickname.to_s, name, ":#{topic}")
        user.send_message(Server.clean_name, Numerics::RPL_TOPICTIME, user.nickname.to_s, name, "#{topic_setter.try(&.nickname)} #{@topic_set_at.try(&.to_unix)}")
      end

      user.send_message(Server.clean_name, Numerics::RPL_NAMREPLY, user.nickname.to_s, "=", name, ":#{users.map(&.to_s).join(" ")}")
      user.send_message(Server.clean_name, Numerics::RPL_ENDOFNAMES, user.nickname.to_s, name, ":End of NAMES list")
    end

    def remove_client(user : Client)
      unless user_in_channel?(user)
        user.send_message(Server.clean_name, Numerics::ERR_NOTONCHANNEL, irc_name, ":You're not on that channel")
        return
      end
      @users.delete(find_user(user))
      @users.each do |u|
        u.send_message_to_server("PART", user.nickname.to_s, user.user.try(&.name), user.host, [name])
      end
    end

    def send_message(user : Client, message : String)
      if user_in_channel?(user)
        @users.each do |u|
          next if u.client == user
          u.send_message_to_server("PRIVMSG", user.nickname.to_s, user.user.try(&.name), user.host, [name] + [message])
        end
      else
        user.send_message(Server.clean_name, Numerics::ERR_NOTONCHANNEL, irc_name, ":You have to be in channel to send messages")
      end
    end

    def send_raw(user : Client, command : String, nickname : String, user_name : String, host : String, params : Array(String))
      if user_in_channel?(user)
        @users.each do |u|
          next if u.client == user
          u.send_message_to_server(command, nickname, user_name, host, params)
        end
      else
        user.send_message(Server.clean_name, Numerics::ERR_NOTONCHANNEL, irc_name, ":You have to be in channel to send messages")
      end
    end

    def change_user_mode(sender : Client, target_nick : String, mode : String)
      unless user_in_channel?(sender)
        sender.send_message(Server.clean_name, Numerics::ERR_NOTONCHANNEL, irc_name, ":You're not on that channel")
        return
      end
      channel_user = find_user(sender)
      target_user = find_user_by_nickname(target_nick)

      if target_user.nil?
        sender.send_message(Server.clean_name, Numerics::ERR_USERNOTINCHANNEL, target_nick, irc_name, ":User is not in the channel")
        return
      end

      if channel_user.try(&.is_operator?) || channel_user.try(&.is_half_operator?)
        # check if it needs to be added or removed
        if mode.starts_with?("+")
          target_user.add_mode(mode[1..-1])
        elsif mode.starts_with?("-")
          target_user.remove_mode(mode[1..-1])
        end
        @users.each do |u|
          u.send_message_to_server("MODE", sender.nickname.to_s, sender.user.try(&.name), sender.host, [name, mode, target_nick])
        end
      else
        sender.send_message(Server.clean_name, Numerics::ERR_CHANOPRIVSNEEDED, irc_name, ":You must be a channel operator or a half-operator")
      end
    end

    def add_ban(mask : String)
      bans << mask
    end

    def remove_ban(mask : String)
      bans.delete(mask)
    end

    def is_banned?(user : Client) : Bool
      hostmask = "#{user.nickname}!#{user.user.try(&.name)}@#{user.host}"
      bans.any? do |ban|
        regex = Regex.new(ban.gsub(".", "\\.").gsub("*", ".*"))
        regex =~ hostmask
      end
    end

    def secret?
      has_mode?("s")
    end

    def change_channel_mode(sender : Client, mode : String, target_nick : String? = nil)
      unless user_in_channel?(sender)
        sender.send_message(Server.clean_name, Numerics::ERR_NOTONCHANNEL, irc_name, ":You're not on that channel")
        return
      end

      channel_user = find_user(sender)

      if mode.starts_with?("+") || mode.starts_with?("-")
        mode_action = mode[0]
        mode_flags = mode[1..-1]

        mode_flags.each_char do |flag|
          case flag
          when 'o', 'h', 'v'
            if target_nick.nil?
              sender.send_message(Server.clean_name, Numerics::ERR_NEEDMOREPARAMS, "MODE", ":Not enough parameters")
            else
              change_user_mode(sender, target_nick, "#{mode_action}#{flag}")
            end
          when 'l'
            if channel_user.try(&.is_operator?)
              if target_nick.nil?
                sender.send_message(Server.clean_name, Numerics::ERR_NEEDMOREPARAMS, "MODE", ":Not enough parameters")
              else
                change_channel_limit(sender, mode_action, target_nick.to_i)
              end
            else
              sender.send_message(Server.clean_name, Numerics::ERR_CHANOPRIVSNEEDED, irc_name, ":You must be a channel operator")
            end
          when 'i', 'm', 'n', 't', 's', 'k', 'b'
            if channel_user.try(&.is_operator?)
              handle_channel_mode(sender, mode_action, flag)
            else
              sender.send_message(Server.clean_name, Numerics::ERR_CHANOPRIVSNEEDED, irc_name, ":You must be a channel operator")
            end
          else
            sender.send_message(Server.clean_name, Numerics::ERR_UNKNOWNMODE, flag, ":Unknown mode flag")
          end
        end
      else
        sender.send_message(Server.clean_name, Numerics::ERR_UNKNOWNMODE, mode, ":Unknown mode flag")
      end
    end

    PARAM_PLACEHOLDER = "PARAM"

    def handle_channel_mode(sender : Client, mode_action : Char, flag : Char)
      # Handle channel mode changes here

      plus = mode_action == "+"
      minus = mode_action == "-"

      if ['i', 'm', 'n', 't', 's'].includes?(flag)
        if plus
          add_mode(flag.to_s)
        elsif minus
          remove_mode(flag.to_s)
        end
      elsif ['k', 'l', 'b'].includes?(flag)
        if plus
          add_mode(flag.to_s, PARAM_PLACEHOLDER)
        elsif minus
          remove_mode(flag.to_s)
        end
      else
        sender.send_message(Server.clean_name, Numerics::ERR_UNKNOWNMODE, flag, ":Unknown mode flag")
      end

      @users.each do |u|
        u.send_message_to_server("MODE", sender.nickname.to_s, sender.user.try(&.name), sender.host, [name, "#{mode_action}#{flag}"])
      end
    end

    def change_channel_limit(sender : Client, mode_action : Char, new_limit : Int32)
      channel_user = find_user(sender)

      if channel_user.try(&.is_operator?) || channel_user.try(&.is_half_operator?)
        if mode_action == "+"
          add_mode("l", new_limit.to_s)
        elsif mode_action == "-"
          remove_mode("l")
        end
        @users.each do |u|
          u.send_message_to_server("MODE", sender.nickname.to_s, sender.user.try(&.name), sender.host, [name, "#{mode_action}l", new_limit.to_s])
        end
      else
        sender.send_message(Server.clean_name, Numerics::ERR_CHANOPRIVSNEEDED, irc_name, ":You must be a channel operator or a half-operator")
      end
    end

    def add_mode(mode : String, param : String? = nil)
      if param
        modes[mode] = "#{mode}=#{param}"
      else
        modes[mode] = mode
      end
    end

    def remove_mode(mode : String)
      modes.delete(mode)
    end

    def has_mode?(mode : String) : Bool
      modes.any? { |_, value| value && value.starts_with?(mode) }
    end

    def get_mode_param(mode : String) : String?
      mode_entry = modes.find { |_, value| value && value.starts_with?(mode) }
      mode_entry.try { |_, value| value && value.split('=').try(&.[1]) }
    end    

    def private?
      has_mode?("p")
    end

    def channel_password
      get_mode_param("k")
    end

    def user_in_channel?(user)
      @users.any? { |u| u.client == user }
    end

    def find_user(user)
      @users.find { |u| u.client == user }
    end

    def find_user_by_nickname(nickname : String)
      @users.find { |u| u.nickname == nickname }
    end

    def delete(user : Client)
      @users.delete(find_user(user))
    end

    def delete(nickname : String)
      @users.delete(find_user_by_nickname(nickname))
    end

    def delete(user : ChannelUser)
      @users.delete(user)
    end

    def channel_full? : Bool
      # get the limit from the channel modes
      limit = get_mode_param("l").try(&.to_i) || 0
      limit != 0 && @users.size >= limit
    end

    def channel_empty?
      @users.empty?
    end

    def irc_name
      ":#{@name}"
    end

  end
end
