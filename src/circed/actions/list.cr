module Circed
  class Actions::List
    extend Circed::ActionHelper

    def self.call(sender)
      send_reply(sender, Numerics::RPL_LISTSTART, "Channel", "Users  Name", " :Start of /LIST")

      ChannelHandler.channels.each do |name, channel|
        next if channel.secret? && !channel.users.includes?(sender.user)

        user_count = channel.users.size
        topic = channel.topic.empty? ? "No topic is set" : channel.topic
        send_reply(sender, Numerics::RPL_LIST, name, user_count, " :#{topic}")
      end

      send_reply(sender, Numerics::RPL_LISTEND, " :End of /LIST")
    end

    private def self.send_reply(sender, numeric, *params)
      message = ":#{Server.clean_name} #{numeric} #{sender.nickname} #{params.join(" ")}"
      sender.send_message(message)
    end
  end
end
