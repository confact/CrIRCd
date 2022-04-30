module Circed
  class Actions::Invite

    @@command = "INVITE"

    extend Circed::ActionHelper
  
    def self.call(sender, receiver, message)
      invited_user = receiver
      channel = message[1]
      if channel.starts_with?("#")
        if ChannelHandler.channel_exists?(channel)
          client = UserHandler.get_client(invited_user)
          if client
            send_to_user(client) do |_receiver, io|
              next if io.nil?
              parse(sender, message, io)
            end
            send_to_user(sender) do |_receiver, io|
              next if io.nil?
              parse(sender, message, io)
            end
          else
            send_error(sender, Numerics::ERR_NOSUCHNICK, invited_user, "No such nick")
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