require "./base_action"

module Circed
  class Actions::List < Actions::BaseAction
    protected def self.execute_action(sender : Client, channel_names : String? = nil) : Nil
      send_reply(sender, Numerics::RPL_LISTSTART, "Channel", ":Users Name")

      if channel_names
        Utils::IrcUtils.each_list_param(channel_names) do |channel_name|
          channel_repository[channel_name]?.try { |channel| send_channel(sender, channel) }
        end
      else
        channel_repository.each { |channel| send_channel(sender, channel) }
      end

      send_reply(sender, Numerics::RPL_LISTEND, ":End of /LIST")
    end

    private def self.send_channel(sender : Client, channel : Domain::Channel) : Nil
      return unless channel.visible_to?(sender.nickname)

      topic = channel.topic.presence || "No topic is set"
      send_reply(sender, Numerics::RPL_LIST, channel.name, channel.member_count, ":#{topic}")
    end

    private def self.send_reply(sender : Client, numeric : String, *params)
      sender.send_message(Server.clean_name, numeric, sender.nickname, *params)
    end
  end
end
