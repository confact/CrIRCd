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

      channels_list = target.channels.map(&.name.as(String)).join(" ")
      sender.send_message(Server.clean_name, Numerics::RPL_WHOISCHANNELS, sender.nickname, target.nickname, ":#{channels_list}")

      if domain_user = user_repo.get(target_nickname)
        if domain_user.modes.includes?('o') || domain_user.modes.includes?('O')
          sender.send_message(Server.clean_name, Numerics::RPL_WHOISOPERATOR, sender.nickname, target.nickname, ":is an IRC operator")
        end

        if away_message = domain_user.away_message
          sender.send_message(Server.clean_name, Numerics::RPL_AWAY, sender.nickname, target.nickname, ":#{away_message}")
        end
      end

      idle_time_seconds = (Time.utc - target.last_activity).to_i
      sender.send_message(Server.clean_name, Numerics::RPL_WHOISIDLE, sender.nickname, target.nickname, idle_time_seconds, target.signon_time.to_unix, ":seconds idle, signon time")

      sender.send_message(Server.clean_name, Numerics::RPL_ENDOFWHOIS, sender.nickname, target.nickname, ":End of WHOIS list")
    end
  end
end
