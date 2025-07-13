module Circed
  class Actions::List
    extend Circed::ActionHelper

    def self.call(sender)
      send_reply(sender, Numerics::RPL_LISTSTART, "Channel", "Users  Name", " :Start of /LIST")

      # Get all channels from repository
      channel_repo = Infrastructure::ServiceLocator.channel_repository
      channel_repo.all.each do |channel|
        # Check secret mode and user access
        next if channel.is_secret? && !channel.has_member?(sender.nickname.to_s)
        # next if channel.modes.includes?('s') && !channel.has_member?(sender.nickname)

        user_count = channel.member_count
        topic = channel.topic.nil? || channel.topic.try(&.empty?) ? "No topic is set" : channel.topic
        send_reply(sender, Numerics::RPL_LIST, channel.name, user_count, " :#{topic}")
      end

      send_reply(sender, Numerics::RPL_LISTEND, " :End of /LIST")
    end

    private def self.send_reply(sender, numeric, *params)
      message = ":#{Server.clean_name} #{numeric} #{sender.nickname} #{params.join(" ")}"
      sender.send_message(message)
    end
  end
end
