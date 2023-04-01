module Circed
  class Actions::Join
    extend Circed::ActionHelper

    def self.call(sender, channel : String, password : String? = nil)
      channels = channel.split(",")
      channels.each do |ch|
        ch = ch.strip
        if ch.empty?
          send_error(sender, Numerics::ERR_NOSUCHCHANNEL, ch, "No such channel")
          next
        end
        if ChannelHandler.channel_is_full?(ch)
          send_error(sender, Numerics::ERR_CHANNELISFULL, ch, "Channel is full")
          next
        end
        if ChannelHandler.user_in_channel?(ch, sender)
          send_error(sender, Numerics::ERR_USERONCHANNEL, ch, "User is already in channel")
          next
        end
        if ChannelHandler.channel_is_private?(ch)
          send_error(sender, Numerics::ERR_INVITEONLYCHAN, ch, "Channel is invite only")
          next
        end

        if ChannelHandler.channel_has_password?(ch)
          if password.nil?
            send_error(sender, Numerics::ERR_BADCHANNELKEY, ch, "Channel has a password")
            next
          end
          if password != ChannelHandler.channel_password(ch)
            send_error(sender, Numerics::ERR_BADCHANNELKEY, ch, "Channel has a password")
            next
          end
        end
        #
        add_user_to_channel(ch, sender)
        # send_message(Server.clean_name, "JOIN", channel)
      end
    end

    def self.add_user_to_channel(channel, user)
      ChannelHandler.add_user_to_channel(channel, user)
    end
  end
end
