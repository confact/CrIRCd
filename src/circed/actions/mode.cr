module Circed
  class Actions::Mode
    extend Circed::ActionHelper

    def self.call(sender, message : Array(String))
      return if message.empty?

      user_or_channel = message.first
      if user_or_channel.starts_with?("#")
        channel = ChannelHandler.get_channel(user_or_channel)
        if channel
          if message.size > 1 && (message[1].starts_with?("+") || message[1].starts_with?("-"))
            # channel mode
            target_nick = message[2]?
            channel.change_channel_mode(sender, message[1], target_nick)
          else
            # user mode
            if message.size > 1
              target_nick = message[1]
              channel.change_user_mode(sender, target_nick, message[2..-1].join)
            end
          end
        else
          send_error(sender, Numerics::ERR_NOSUCHCHANNEL, user_or_channel, "No such channel")
        end
      else
        client = UserHandler.get_client(user_or_channel)
        if client
          # client.not_nil!.mode(self, message[1..-1].join)
        else
          send_error(sender, Numerics::ERR_NOSUCHNICK, user_or_channel, "No such nick")
        end
      end
    end
  end
end
