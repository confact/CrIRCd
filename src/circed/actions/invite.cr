require "./base_action"

module Circed
  class Actions::Invite < Actions::ChannelAction
    protected def self.execute_action(sender : Client, receiver : String, message : Array(String)) : Nil
      invited_user = receiver
      channel = message[1]
      if channel.starts_with?("#")
        channel_repository = get_channel_repository
        if channel_repository.exists?(channel)
          user_repository = get_user_repository
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
            Utils::IrcUtils.send_no_such_nick_error(sender, invited_user)
          end
        else
          Utils::IrcUtils.send_no_such_channel_error(sender, channel)
        end
      else
        Utils::IrcUtils.send_channel_error(sender, channel)
      end
    end
  end
end
