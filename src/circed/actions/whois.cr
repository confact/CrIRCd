require "./base_action"

module Circed
  class Actions::Whois < Actions::UserAction
    protected def self.execute_action(sender : Client, target_nickname : String) : Nil
      user_repository = get_user_repository
      target = user_repository.get_client(target_nickname)

      if target.nil?
        Utils::IrcUtils.send_no_such_nick_error(sender, target_nickname)
        return
      end

      user = target.user

      sender.send_message(Server.clean_name, Numerics::RPL_WHOISUSER, sender.nickname, target.nickname, user.try(&.name), target.host, "*", ":#{user.try(&.realname)}")
      sender.send_message(Server.clean_name, Numerics::RPL_WHOISSERVER, sender.nickname, target.nickname, Server.name, ":#{Server.config.host}")

      channels_list = target.channels.map(&.name.as(String)).join(" ")
      sender.send_message(Server.clean_name, Numerics::RPL_WHOISCHANNELS, sender.nickname, target.nickname, ":#{channels_list}")

      idle_time_seconds = (Time.utc - target.last_activity).to_i
      sender.send_message(Server.clean_name, Numerics::RPL_WHOISIDLE, sender.nickname, target.nickname, idle_time_seconds, target.signon_time.to_unix, ":seconds idle, signon time")
      # You can add more WHOIS replies here, such as RPL_WHOISOPERATOR, RPL_WHOISIDLE, etc.

      sender.send_message(Server.clean_name, Numerics::RPL_ENDOFWHOIS, sender.nickname, target.nickname, ":End of WHOIS list")
    end
  end
end
