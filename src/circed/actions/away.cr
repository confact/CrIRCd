require "./base_action"

module Circed
  class Actions::Away < Actions::BaseAction
    protected def self.execute_action(sender : Client, away_message : String? = nil) : Nil
      nickname = sender.nickname
      return unless nickname

      user_repo = user_repository
      user = user_repo.get(nickname)

      unless user
        Utils::IrcUtils.send_no_such_nick_error(sender, nickname)
        return
      end

      if away_message.nil? || away_message.empty?
        # User is coming back (unaway)
        user.away_message = nil

        # Send RPL_UNAWAY
        sender.send_message(
          Server.clean_name,
          Numerics::RPL_UNAWAY,
          nickname,
          ":You are no longer marked as being away"
        )

        # Propagate to network
        propagate_away_to_network(sender, nil)
      else
        # User is going away
        user.away_message = away_message

        # Send RPL_NOWAWAY
        sender.send_message(
          Server.clean_name,
          Numerics::RPL_NOWAWAY,
          nickname,
          ":You have been marked as being away"
        )

        # Propagate to network
        propagate_away_to_network(sender, away_message)
      end

      # Update user repository
      user_repo.add(nickname, user)

      # Update network state
      sync_away_with_network(nickname, away_message)
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

    private def self.sync_away_with_network(nickname : String, away_message : String?)
      # Update network state with away status
      if user = Network::NetworkState.get_user(nickname)
        user.away_message = away_message
      end
    end
  end
end
