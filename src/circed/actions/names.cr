require "./base_action"

module Circed
  class Actions::Names < Actions::BaseAction
    protected def self.execute_action(sender : Client, channel_name : String? = nil) : Nil
      channel_repo = channel_repository

      if channel_name.nil? || channel_name.empty?
        channel_repo.each do |channel|
          send_names_reply(sender, channel) if channel.visible_to?(sender.nickname)
        end
        send_end_of_names(sender, "*")
      else
        Utils::IrcUtils.each_list_param(channel_name) do |name|
          send_names_for_channel(sender, channel_repo, name)
        end
      end
    end

    private def self.send_names_for_channel(sender : Client, channel_repo : Repositories::ChannelRepository, channel_name : String)
      if (channel = channel_repo[channel_name]?) && channel.visible_to?(sender.nickname)
        send_names_reply(sender, channel)
      end

      send_end_of_names(sender, channel_name)
    end

    private def self.send_names_reply(sender : Client, channel : Domain::Channel)
      Infrastructure::ServiceLocator.irc_service.send_names_reply(sender, channel)
    end

    private def self.send_end_of_names(sender : Client, channel_name : String)
      sender.send_message(
        Server.clean_name,
        Numerics::RPL_ENDOFNAMES,
        sender.nickname || "*",
        channel_name,
        ":End of /NAMES list"
      )
    end
  end
end
