require "./base_action"

module Circed
  class Actions::Who < Actions::BaseAction
    protected def self.execute_action(sender : Client, target : String? = nil, operators_only : Bool = false) : Nil
      mask = target || "0"
      mask = "0" if mask.empty?
      if Utils::IrcUtils.valid_channel_name?(mask)
        who_channel(sender, mask, operators_only)
      else
        who_users(sender, mask, operators_only)
      end
    end

    private def self.who_channel(sender : Client, channel_name : String, operators_only : Bool)
      unless channel = channel_repository[channel_name]?
        send_end_of_who(sender, channel_name)
        return
      end

      unless channel.visible_to?(sender.nickname)
        send_end_of_who(sender, channel_name)
        return
      end

      channel.members.each do |nickname, modes|
        next unless user = Network::NetworkState.get_user(nickname)
        next if operators_only && !operator?(user)
        next unless visible_to?(sender, user)

        send_who_reply(sender, user, channel, modes)
      end

      send_end_of_who(sender, channel_name)
    end

    private def self.who_users(sender : Client, mask : String, operators_only : Bool)
      Network::NetworkState.users.each_value do |user|
        next if operators_only && !operator?(user)
        next unless visible_to?(sender, user)
        next unless mask == "0" || mask == "*" || matches_mask?(user, mask)

        channel = find_common_channel(sender.nickname, user.nickname)
        modes = channel.try(&.member_modes?(user.nickname))
        send_who_reply(sender, user, channel, modes)
      end

      send_end_of_who(sender, mask)
    end

    private def self.find_common_channel(sender_nickname : String?, target_nickname : String) : Domain::Channel?
      return unless sender_nickname

      channel_repository.each_user_channel(sender_nickname) do |channel|
        return channel if channel.has_member?(target_nickname)
      end

      nil
    end

    private def self.matches_mask?(user : Network::NetworkState::UserInfo, mask : String) : Bool
      Domain::Wildcard.match?(mask, user.nickname) ||
        Domain::Wildcard.match?(mask, user.username) ||
        Domain::Wildcard.match?(mask, user.hostname) ||
        Domain::Wildcard.match?(mask, user.server) ||
        Domain::Wildcard.match?(mask, user.realname)
    end

    private def self.visible_to?(sender : Client, user : Network::NetworkState::UserInfo) : Bool
      return true if sender.nickname.try { |nickname| Domain::CaseMapping.same?(nickname, user.nickname) }
      return true unless user_modes(user).includes?('i')

      !find_common_channel(sender.nickname, user.nickname).nil?
    end

    private def self.user_modes(user : Network::NetworkState::UserInfo) : Set(Char)
      user_repository[user.nickname]?.try(&.modes) || user.modes
    end

    private def self.operator?(user : Network::NetworkState::UserInfo) : Bool
      Domain::User::OPERATOR_MODES.any? { |mode| user_modes(user).includes?(mode) }
    end

    private def self.send_who_reply(sender : Client, user : Network::NetworkState::UserInfo,
                                    channel : Domain::Channel? = nil, modes : Set(Char)? = nil)
      channel_name = channel.try(&.name) || "*"

      sender.send_message(
        Server.clean_name,
        Numerics::RPL_WHOREPLY,
        sender.nickname || "*",
        channel_name,
        user.username,
        user.hostname,
        user.server,
        user.nickname,
        who_flags(user, channel, modes),
        ":#{user.hopcount} #{user.realname}"
      )
    end

    private def self.who_flags(user : Network::NetworkState::UserInfo, channel : Domain::Channel?, modes : Set(Char)?) : String
      String.build(capacity: 3) do |io|
        io << (user.away_message ? 'G' : 'H')
        io << '*' if operator?(user)
        if channel && modes && (prefix = Domain::Channel.member_prefix(modes))
          io << prefix
        end
      end
    end

    private def self.send_end_of_who(sender : Client, target : String)
      sender.send_message(
        Server.clean_name,
        Numerics::RPL_ENDOFWHO,
        sender.nickname || "*",
        target,
        ":End of /WHO list"
      )
    end
  end
end
