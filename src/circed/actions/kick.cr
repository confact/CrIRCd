module Circed
  class Actions::Kick

    extend Circed::ActionHelper

    def self.call(sender, message)
      Log.debug { "kick: #{message}" }
      channel = message.first
      if channel.starts_with?("#")
        if ChannelHandler.channel_exists?(channel)
          channel_obj = ChannelHandler.get_channel(channel).not_nil!
          kick(sender, channel_obj, message[1], message[2..-1].join)
        else
          send_error(sender, Numerics::ERR_NOSUCHCHANNEL, channel, "No such channel")
        end
      else
        send_error(sender, Numerics::ERR_BADCHANMASK, channel, "Wrong channel format")
      end
    end

    def self.kick(sender : Client, channel : Channel, kick_nickname, message)
      unless channel.user_in_channel?(sender)
        send_error(sender, Numerics::ERR_NOTONCHANNEL, channel.name, "You're not on that channel")
        return
      end

      channel_user = channel.find_user(sender).not_nil!

      if !channel_user.is_operator?
        send_error(sender, Numerics::ERR_CHANOPRIVSNEEDED, channel.name, "You're not an operator")
        return
      end

      kicked_user = channel.find_user_by_nickname(kick_nickname)

      if !kicked_user
        send_error(sender, Numerics::ERR_NOSUCHNICK, channel.name, "No such nick/channel")
        return
      end

      send_to_channel(channel) do |receiver, io|
        parse(sender, [channel.name, kicked_user.nickname.to_s, message], io) if io
      end
      channel.delete(kicked_user)

      if !channel_user.try(&.is_operator?)
        send_error(sender, Numerics::ERR_CHANOPRIVSNEEDED, channel.name, "You must be a channel operator")
        return
      end
    end
  end
end
