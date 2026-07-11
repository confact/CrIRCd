require "./base_action"

module Circed
  class Actions::Whois < Actions::BaseAction
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

      channels_list = String.build do |io|
        first = true
        target.each_channel do |channel|
          next unless channel.visible_to?(sender.nickname)

          if first
            first = false
          else
            io << ' '
          end
          if target_nick = target.nickname
            if modes = channel.member_modes?(target_nick)
              if prefix = Domain::Channel.member_prefix(modes)
                io << prefix
              end
            end
          end
          io << channel.name
        end
      end
      sender.send_message(Server.clean_name, Numerics::RPL_WHOISCHANNELS, sender.nickname, target.nickname, ":#{channels_list}")

      if domain_user = user_repo[target_nickname]?
        if domain_user.irc_operator?
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
