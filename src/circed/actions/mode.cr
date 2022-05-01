module Circed
  class Actions::Mode

    @@command = "MODE"

    extend Circed::ActionHelper

    def self.call(sender, message)
      user_or_channel = message.first
      if user_or_channel.starts_with?("#")
        channel = ChannelHandler.get_channel(user_or_channel)
        if channel
          channel.change_channel_mode(sender, message[1..-1].join)
        else
          send_error(sender, Numerics::ERR_NOSUCHCHANNEL, user_or_channel, "No such channel")
        end
      else
        client = UserHandler.get_client(user_or_channel)
        if client
          #client.not_nil!.mode(self, message[1..-1].join)
        else
          send_error(sender, Numerics::ERR_NOSUCHNICK, user_or_channel, "No such nick")
        end
      end
    end
  end
end
