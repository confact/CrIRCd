require "./base_action"

module Circed
  class Actions::Kick < Actions::BaseAction
    protected def self.execute_action(sender : Client, message : Array(String)) : Nil
      Log.debug { "kick: #{message}" }

      channel_names = Utils::IrcUtils.split_list_param(message.first)
      kicked_nicknames = Utils::IrcUtils.split_list_param(message[1])
      reason = Utils::IrcUtils.trailing_param(message, 2) if message.size > 2
      irc_service = Infrastructure::ServiceLocator.irc_service

      if channel_names.size == 1
        channel_name = channel_names.first
        return unless Utils::IrcUtils.validate_channel_name(sender, channel_name)

        kicked_nicknames.each do |kicked_nickname|
          irc_service.kick_user(sender, channel_name, kicked_nickname, reason)
        end
      elsif channel_names.size == kicked_nicknames.size
        channel_names.each_with_index do |target_channel_name, index|
          next unless Utils::IrcUtils.validate_channel_name(sender, target_channel_name)

          irc_service.kick_user(sender, target_channel_name, kicked_nicknames[index], reason)
        end
      else
        sender.send_message(Server.clean_name, Numerics::ERR_NEEDMOREPARAMS, sender.nickname || "*", "KICK", ":Not enough parameters")
      end
    end
  end
end
