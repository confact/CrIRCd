require "./services_manager"

module Circed::Services
  # Channel management integration with ChanServ
  class ChannelManager
    # Handle user joining a registered channel
    def self.on_user_join(channel_name : String, user_nick : String)
      return unless ServicesManager.channel_registered?(channel_name)

      registered_channel = ServicesManager.chanserv.try(&.get_registered_channel(channel_name))
      return unless registered_channel

      # Check if channel is empty and apply registered settings
      if channel = Infrastructure::ServiceLocator.channel_repository.get(channel_name)
        # If user is the first in an empty registered channel, restore settings
        if channel.member_count == 1
          restore_channel_settings(channel_name, registered_channel)
        end

        # Apply user access level
        access_level = registered_channel.get_access_level(user_nick)
        apply_user_access(channel_name, user_nick, access_level)
      end
    end

    # Restore channel settings from ChanServ registration
    private def self.restore_channel_settings(channel_name : String, registered_channel : RegisteredChannel)
      if channel = Infrastructure::ServiceLocator.channel_repository.get(channel_name)
        # Set topic if registered channel has one
        if topic = registered_channel.topic
          channel.topic = topic
          channel.topic_set_by = "ChanServ"
          channel.topic_set_at = Time.utc

          # Announce topic to all members
          channel.members.each_key do |member|
            if client = Infrastructure::ServiceLocator.user_repository.get_client(member)
              client.send_message(":ChanServ!services@#{Server.config.host} TOPIC #{channel_name} :#{topic}")
            end
          end
        end

        # Apply channel modes
        apply_channel_modes(channel, registered_channel.modes)

        # Update last used timestamp
        Database.db.exec(
          "UPDATE registered_channels SET last_used = CURRENT_TIMESTAMP WHERE channel_name = ?",
          channel_name
        )
      end
    end

    # Apply access level modes to user
    private def self.apply_user_access(channel_name : String, user_nick : String, access_level : AccessLevel)
      return if access_level == AccessLevel::None

      if channel = Infrastructure::ServiceLocator.channel_repository.get(channel_name)
        case access_level
        when .founder?, .admin?
          # Grant operator status
          if user_modes = channel.members[user_nick]?
            user_modes.add('o')
            notify_mode_change(channel_name, "+o", user_nick)
          end
        when .operator?
          # Grant operator status
          if user_modes = channel.members[user_nick]?
            user_modes.add('o')
            notify_mode_change(channel_name, "+o", user_nick)
          end
        when .voice?
          # Grant voice
          if user_modes = channel.members[user_nick]?
            user_modes.add('v')
            notify_mode_change(channel_name, "+v", user_nick)
          end
        end
      end
    end

    # Apply channel modes from registration
    private def self.apply_channel_modes(channel : Domain::Channel, mode_string : String)
      # Parse mode string (e.g., "+nt")
      return unless mode_string.starts_with?('+')

      modes = mode_string[1..].chars
      modes.each do |mode_char|
        case mode_char
        when 'n' # No external messages
          channel.modes.add('n')
        when 't' # Topic lock
          channel.modes.add('t')
        when 'm' # Moderated
          channel.modes.add('m')
        when 's' # Secret
          channel.modes.add('s')
        when 'p' # Private
          channel.modes.add('p')
        when 'i' # Invite only
          channel.modes.add('i')
        end
      end
    end

    # Notify channel members of mode change
    private def self.notify_mode_change(channel_name : String, mode : String, target : String)
      if channel = Infrastructure::ServiceLocator.channel_repository.get(channel_name)
        channel.members.each_key do |member|
          if client = Infrastructure::ServiceLocator.user_repository.get_client(member)
            client.send_message(":ChanServ!services@#{Server.config.host} MODE #{channel_name} #{mode} #{target}")
          end
        end
      end
    end

    # Check if user can perform channel operation based on ChanServ access
    def self.check_channel_permission(channel_name : String, user_nick : String, required_level : AccessLevel) : Bool
      return true unless ServicesManager.channel_registered?(channel_name)

      access_level = ServicesManager.get_channel_access(channel_name, user_nick)
      access_level >= required_level
    end
  end
end
