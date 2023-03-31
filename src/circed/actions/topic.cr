module Circed
  class Actions::Topic

    extend Circed::ActionHelper

    def self.call(sender : Client, message : Array(String))
      channel = message.first
      if channel.starts_with?("#")
        if ChannelHandler.channel_exists?(channel)
          channel_obj = ChannelHandler.get_channel(channel)
          if channel_obj.nil?
            send_error(sender, Numerics::ERR_NOSUCHCHANNEL, channel, "Channel #{channel} does not exist.")
            return
          end

          channel_obj = channel_obj.not_nil!

          if !channel_obj.user_in_channel?(sender)
            send_error(sender, Numerics::ERR_NOTONCHANNEL, channel, "You're not on that channel")
            return
          end

          channel_user = channel_obj.find_user(sender)

          if channel_user.nil?
            send_error(sender, Numerics::ERR_NOTONCHANNEL, channel, "You're not on that channel")
            return
          end

          channel_user = channel_user.not_nil!
          topic = message[1..-1].join(" ")

          if channel_user.is_operator?
            channel_obj.topic = topic
            channel_obj.topic_setter = channel_user
            channel_obj.topic_set_at = Time.utc
            send_to_channel(channel_obj) do |receiver, io|
              parse(sender, [channel, topic], io) if io
            end
          else
            send_error(sender, Numerics::ERR_CHANOPRIVSNEEDED, channel, "You're not an operator on that channel")
          end
        else
          send_error(sender, Numerics::ERR_NOSUCHCHANNEL, channel, "No such channel")
        end
      else
        send_error(sender, Numerics::ERR_BADCHANMASK, channel, "Wrong channel format")
      end
    end
  end
end
