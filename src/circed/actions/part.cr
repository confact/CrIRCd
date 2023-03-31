module Circed
  class Actions::Part

    extend Circed::ActionHelper

    def self.call(sender, channel : String)
      channels = channel.split(",")
      channels.each do |ch|
        ch = ch.strip
        if ch.empty?
          send_error(sender, Numerics::ERR_NOSUCHCHANNEL, ch, "No such channel")
          next
        end
        if !ChannelHandler.channel_exists?(ch)
          send_error(sender, Numerics::ERR_NOSUCHCHANNEL, ch, "No such channel")
          next
        end
        if !ChannelHandler.user_in_channel?(ch, sender)
          send_error(sender, Numerics::ERR_NOTONCHANNEL, ch, "User is not in channel")
          next
        end
        ChannelHandler.remove_user_from_channel(ch, sender)
        #send_message(Server.clean_name, "PART", channel)
      end
    end
  end
end
