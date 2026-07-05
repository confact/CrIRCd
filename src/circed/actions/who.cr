require "./base_action"

module Circed
  class Actions::Who < Actions::BaseAction
    protected def self.execute_action(sender : Client, target : String? = nil) : Nil
      if target.nil? || target.empty?
        # List all users (usually not recommended for performance)
        # Some implementations limit this to operators only
        send_end_of_who(sender, "*")
        return
      end

      if target.starts_with?('#') || target.starts_with?('&')
        # WHO for a channel
        who_channel(sender, target)
      else
        # WHO for a user
        who_user(sender, target)
      end
    end

    private def self.who_channel(sender : Client, channel_name : String)
      channel_repo = channel_repository
      user_repo = user_repository

      unless channel = channel_repo.get(channel_name)
        send_end_of_who(sender, channel_name)
        return
      end

      # Check if user can see this channel
      unless can_see_channel?(sender, channel)
        send_end_of_who(sender, channel_name)
        return
      end

      # Send WHO replies for each member
      channel.members.each do |nickname, modes|
        if client = user_repo.get_client(nickname)
          send_who_reply(sender, client, channel, modes)
        end
      end

      send_end_of_who(sender, channel_name)
    end

    private def self.who_user(sender : Client, target : String)
      user_repo = user_repository

      if client = user_repo.get_client(target)
        # Find a common channel or just send basic info
        channel = find_common_channel(sender, client)

        send_who_reply(sender, client, channel)
      end

      send_end_of_who(sender, target)
    end

    private def self.can_see_channel?(sender : Client, channel : Domain::Channel) : Bool
      # User can see channel if:
      # 1. They are in the channel
      # 2. Channel is not secret

      if nickname = sender.nickname
        return true if channel.has_member?(nickname)
      end
      return false if channel.secret?

      true
    end

    private def self.find_common_channel(sender : Client, target : Client) : Domain::Channel?
      sender_nick = sender.nickname
      target_nick = target.nickname
      return nil unless sender_nick && target_nick

      channel_repo = channel_repository
      sender_channels = channel_repo.find_user_channels(sender_nick)
      target_channels = channel_repo.find_user_channels(target_nick)

      # Find first common channel
      sender_channels.each do |channel|
        if target_channels.any? { |target_channel| target_channel.name == channel.name }
          return channel
        end
      end

      nil
    end

    private def self.send_who_reply(sender : Client, client : Client, channel : Domain::Channel? = nil, modes : Set(Char)? = nil)
      # WHO reply format:
      # :server 352 nick channel username host server nick flags :hopcount realname

      user = client.user
      return unless user

      # Channel name or "*" if no channel
      channel_name = channel ? channel.name : "*"

      # Host information
      hostname = client.host || "unknown"

      sender.send_message(
        Server.clean_name,
        Numerics::RPL_WHOREPLY,
        sender.nickname || "*",
        channel_name,
        user.name,
        hostname,
        Server.clean_name,
        client.nickname || "*",
        who_flags(sender, client, channel, modes),
        ":0 #{user.realname}"
      )
    end

    private def self.who_flags(sender : Client, client : Client, channel : Domain::Channel?, modes : Set(Char)?) : String
      flags = "H"
      flags += "*" if client.nickname == sender.nickname
      if channel && (prefix = channel_mode_prefix(modes))
        flags += prefix.to_s
      end
      flags
    end

    private def self.channel_mode_prefix(modes : Set(Char)?) : Char?
      return nil unless modes

      return '@' if modes.includes?('o')
      return '+' if modes.includes?('v')
    end

    private def self.send_end_of_who(sender : Client, target : String)
      # Send RPL_ENDOFWHO
      # Format: :server 315 nick target :End of /WHO list
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
