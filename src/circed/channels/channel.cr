module Circed
  class Channel
    getter name : String

    property topic : String = ""
    property topic_setter : ChannelUser? = nil
    property topic_set_at : Time? = nil

    getter mode : String = ""

    getter users : Array(ChannelUser) = [] of ChannelUser

    def initialize(name)
      if name.starts_with?("#")
        @name = name
      else
        @name = "#" + name
      end
    end

    def add_client(user : Client)
      if user_in_channel?(user)
        user.send_message(Server.clean_name, Numerics::ERR_USERONCHANNEL, ":You are already on #{@name}")
        return
      end
      channel_user = ChannelUser.new(user, self)
      if @users.empty?
        channel_user.set_mode("+o")
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

    def change_channel_mode(user : Client, mode : String)
      unless user_in_channel?(user)
        user.send_message(Server.clean_name, Numerics::ERR_NOTONCHANNEL, irc_name, ":You're not on that channel")
        return
      end
      channel_user = find_user(user)

      if mode.starts_with?("+")
        mode.gsub("+", "").split("").each do |m|
          if channel_user.try(&.is_operator?)
            @mode += m
            @users.each do |u|
              u.send_message_to_server("MODE", user.nickname.to_s, user.user.try(&.name), user.host, [name, mode])
            end
          else
            user.send_message(Server.clean_name, Numerics::ERR_CHANOPRIVSNEEDED, irc_name, ":You must be a channel operator")
          end
        end
      end
      if mode.starts_with?("-")
        mode.gsub("-", "").split("").each do |m|
          if channel_user.try(&.is_operator?)
            @mode = @mode.gsub(m, "")
            @users.each do |u|
              u.send_message_to_server("MODE", user.nickname.to_s, user.user.try(&.name), user.host, [name, mode])
            end
          else
            user.send_message(Server.clean_name, Numerics::ERR_CHANOPRIVSNEEDED, irc_name, ":You must be a channel operator")
          end
        end
      end
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

    def channel_full?
      @users.size >= 200
    end

    def channel_empty?
      @users.empty?
    end

    def irc_name
      ":#{@name}"
    end

  end
end
