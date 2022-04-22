module Circed
  class Channel
    getter name : String

    getter topic : String = ""

    getter users : Array(Client) = [] of Client

    def initialize(name)
      @name = name
    end

    def add_client(user : Client)
      if user_in_channel?(user)
        user.send_message(Server.clean_name, Numerics::ERR_USERONCHANNEL, ":You are already on #{@name}")
        return
      end
      @users << user
      @users.each do |u|
        u.send_message_to_server("JOIN", user.nickname.not_nil!, user.user.not_nil!.name, user.host, [name])
      end
      user.send_message(Server.clean_name, Numerics::RPL_TOPIC, name, ":#{@topic}")
      user.send_message(Server.clean_name, Numerics::RPL_NAMREPLY, "=", name, ":#{@users.map { |u| u.nickname }.join(" ")}")
      user.send_message(Server.clean_name, Numerics::RPL_ENDOFNAMES, name, ":End of NAMES list")
    end

    def remove_client(user : Client)
      unless user_in_channel?(user)
        user.send_message(Server.clean_name, Numerics::ERR_NOTONCHANNEL, name, ":You're not on that channel")
        return
      end
      @users.delete(user)
      @users.each do |u|
        u.send_message_to_server("PART", user.nickname.not_nil!, user.user.not_nil!.name, user.host, [name])
      end
    end

    def send_message(user : Client, message : String)
      @users.each do |u|
        next if u == user
        u.send_message_to_server("PRIVMSG", user.nickname.not_nil!, user.user.not_nil!.name, user.host, [name, message])
      end
    end

    def user_in_channel?(user)
      @users.includes?(user)
    end

    def channel_full?
      @users.size >= 200
    end

    def channel_empty?
      @users.empty?
    end

  end
end
