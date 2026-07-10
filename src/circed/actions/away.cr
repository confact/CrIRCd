require "./base_action"

module Circed
  class Actions::Away < Actions::BaseAction
    protected def self.execute_action(sender : Client, away_message : String? = nil) : Nil
      nickname = sender.nickname
      return unless nickname

      unless user = user_repository[nickname]?
        Utils::IrcUtils.send_no_such_nick_error(sender, nickname)
        return
      end

      away_message = nil if away_message.try(&.empty?)
      user.away_message = away_message
      numeric = away_message ? Numerics::RPL_NOWAWAY : Numerics::RPL_UNAWAY
      status = away_message ? "You have been marked as being away" : "You are no longer marked as being away"
      sender.send_message(Server.clean_name, numeric, nickname, ":#{status}")
      propagate_away_to_network(sender, away_message)

      # Update network state
      Network::NetworkState.set_user_away(nickname, away_message)
    end

    private def self.propagate_away_to_network(sender : Client, away_message : String?)
      # Propagate AWAY message to all connected servers
      if away_message.nil?
        message = ":#{sender.hostmask} AWAY"
      else
        message = ":#{sender.hostmask} AWAY :#{away_message}"
      end

      ServerHandler.servers.each do |server|
        server.safe_send(message)
      end
    end
  end
end
