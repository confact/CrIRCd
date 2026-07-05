require "./base_action"

module Circed
  class Actions::Names < Actions::BaseAction
    protected def self.execute_action(sender : Client, channel_name : String? = nil) : Nil
      channel_repo = channel_repository

      if channel_name.nil? || channel_name.empty?
        # List all channels user is in
        if nickname = sender.nickname
          user_channels = channel_repo.find_user_channels(nickname)
          send_end_of_names(sender, "*") if user_channels.empty?
          user_channels.each do |channel|
            send_names_reply(sender, channel)
            send_end_of_names(sender, channel.name)
          end
        end
      else
        split_list_param(channel_name).each do |name|
          send_names_for_channel(sender, channel_repo, name)
        end
      end
    end

    private def self.send_names_for_channel(sender : Client, channel_repo : Repositories::ChannelRepository, channel_name : String)
      if channel = channel_repo.get(channel_name)
        # Check if user can see this channel
        if can_see_channel?(sender, channel)
          send_names_reply(sender, channel)
        else
          # Send empty reply for channels user cannot see
          send_empty_names_reply(sender, channel_name)
        end
      else
        # Channel doesn't exist - send empty reply
        send_empty_names_reply(sender, channel_name)
      end

      # Always end with RPL_ENDOFNAMES
      send_end_of_names(sender, channel_name)
    end

    private def self.split_list_param(param : String) : Array(String)
      param.split(',', remove_empty: true)
    end

    private def self.can_see_channel?(sender : Client, channel : Domain::Channel) : Bool
      # User can see channel if:
      # 1. They are in the channel
      # 2. Channel is not secret
      # 3. Channel is not private (in some implementations)

      if nickname = sender.nickname
        return true if channel.has_member?(nickname)
      end
      return false if channel.secret?

      # For now, allow seeing non-secret channels
      true
    end

    private def self.send_names_reply(sender : Client, channel : Domain::Channel)
      names_string = String.build do |io|
        first = true
        channel.members.each do |nickname, modes|
          if first
            first = false
          else
            io << ' '
          end

          if modes.includes?('o')
            io << '@'
          elsif modes.includes?('h')
            io << '%'
          elsif modes.includes?('v')
            io << '+'
          end

          io << nickname
        end
      end

      # Determine channel type symbol
      channel_type = channel.secret? ? "@" : "="

      # Send RPL_NAMREPLY
      # Format: :server 353 nick = #channel :names
      sender.send_message(
        Server.clean_name,
        Numerics::RPL_NAMREPLY,
        sender.nickname || "*",
        channel_type,
        channel.name,
        ":#{names_string}"
      )
    end

    private def self.send_empty_names_reply(sender : Client, channel_name : String)
      # Send empty names reply for non-existent or hidden channels
      sender.send_message(
        Server.clean_name,
        Numerics::RPL_NAMREPLY,
        sender.nickname || "*",
        "=",
        channel_name,
        ":"
      )
    end

    private def self.send_end_of_names(sender : Client, channel_name : String)
      # Send RPL_ENDOFNAMES
      # Format: :server 366 nick channel :End of /NAMES list
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
