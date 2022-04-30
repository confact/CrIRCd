module Circed
  class Actions::Privmsg

    @@command = "PRIVMSG"

    extend Circed::ActionHelper
  
    def self.call(sender, receiver, message : Array(String))
      if receiver.starts_with?("#")
        channel = ChannelHandler.get_channel(receiver)
        if channel
          send_to_channel(channel) do |_receiver, io|
            next if io.nil?
            next if _receiver == sender
            parse(sender, message, io)
          end
        else
          send_error(sender, Numerics::ERR_NOSUCHCHANNEL, "No such channel")
        end
      else
        client = UserHandler.get_client(receiver)
        if client
          send_to_user(receiver) do |_receiver, io|
            next if io.nil?
            next if _receiver == sender
            parse(sender, message, io)
          end
        else
          send_error(sender, Numerics::ERR_NOSUCHNICK, "No such nick")
        end
      end
    end
  end
end