require "./base_action"

module Circed
  class Actions::Whois < Actions::UserAction
    protected def self.execute_action(sender : Client, target_nickname : String) : Nil
      user_repo = user_repository
      target = user_repo.get_client(target_nickname)

      if target.nil?
        Utils::IrcUtils.send_no_such_nick_error(sender, target_nickname)
        return
      end

      user = target.user

      sender.send_message(Server.clean_name, Numerics::RPL_WHOISUSER, sender.nickname, target.nickname, user.try(&.name), target.host, "*", ":#{user.try(&.realname)}")
      sender.send_message(Server.clean_name, Numerics::RPL_WHOISSERVER, sender.nickname, target.nickname, Server.name, ":#{Server.config.host}")

      # Add services information
      add_services_info(sender, target)

      channels_list = target.channels.map(&.name.as(String)).join(" ")
      sender.send_message(Server.clean_name, Numerics::RPL_WHOISCHANNELS, sender.nickname, target.nickname, ":#{channels_list}")

      idle_time_seconds = (Time.utc - target.last_activity).to_i
      sender.send_message(Server.clean_name, Numerics::RPL_WHOISIDLE, sender.nickname, target.nickname, idle_time_seconds, target.signon_time.to_unix, ":seconds idle, signon time")

      sender.send_message(Server.clean_name, Numerics::RPL_ENDOFWHOIS, sender.nickname, target.nickname, ":End of WHOIS list")
    end

    # Add services-related WHOIS information
    private def self.add_services_info(sender : Client, target : Client)
      sender_nick = sender.nickname
      target_nick = target.nickname
      return unless sender_nick && target_nick

      # Check if user is identified with UserServ
      if Services::ServicesManager.user_identified?(target_nick)
        # Using RPL_WHOISREGNICK (307) - indicates user is identified/registered
        sender.send_message(Server.clean_name, Numerics::RPL_WHOISREGNICK, sender_nick, target_nick, ":is a registered nick")
      end

      # Check if target is a service
      if Services::ServicesManager.service?(target_nick)
        # Using RPL_WHOISSPECIAL (320) - indicates special status
        sender.send_message(Server.clean_name, Numerics::RPL_WHOISSPECIAL, sender_nick, target_nick, ":is a Network Service")
      end

      # Add channel access information for common channels
      add_channel_access_info(sender, target)
    end

    # Add channel access information for channels both users share
    private def self.add_channel_access_info(sender : Client, target : Client)
      sender_nick = sender.nickname
      target_nick = target.nickname
      return unless sender_nick && target_nick

      # Find common channels
      sender_channels = sender.channels.map(&.name).to_set
      target_channels = target.channels.map(&.name).to_set
      common_channels = sender_channels & target_channels

      common_channels.each do |channel_name|
        next unless Services::ServicesManager.channel_registered?(channel_name)

        access_level = Services::ServicesManager.get_channel_access(channel_name, target_nick)
        next if access_level == Services::AccessLevel::None

        access_name = case access_level
                      when .founder?
                        "founder"
                      when .admin?
                        "admin"
                      when .operator?
                        "operator"
                      when .voice?
                        "voice"
                      else
                        next
                      end

        # Using RPL_WHOISSPECIAL (320) to show channel access
        sender.send_message(Server.clean_name, Numerics::RPL_WHOISSPECIAL, sender_nick, target_nick, ":is #{access_name} of #{channel_name}")
      end
    end
  end
end
