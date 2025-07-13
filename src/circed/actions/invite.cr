module Circed
  class Actions::Invite
    extend Circed::ActionHelper

    def self.call(sender, receiver, message)
      invited_user = receiver
      channel = message[1]
      if channel.starts_with?("#")
        channel_repository = Infrastructure::ServiceLocator.channel_repository
        if channel_repository.exists?(channel)
          user_repository = Infrastructure::ServiceLocator.user_repository
          client = user_repository.get_client(invited_user)
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
