# Service for handling user notifications and event broadcasting
module Circed
  module Services
    class NotificationService
      include Core::NotificationService

      def initialize(@user_repository : Repositories::UserRepository,
                     @channel_repository : Repositories::ChannelRepository)
      end

      def notify(event : Core::NotificationEvent, targets : Array(Core::NotificationTarget)) : Void
        targets.each do |target|
          target.receive_notification(event)
        end
      end

      # High-level notification methods
      def notify_user_joined(nickname : String, channel_name : String, exclude_user : Bool = true)
        if user = @user_repository.get(nickname)
          message = ":#{user.hostmask} JOIN #{channel_name}"
          send_to_channel_members(channel_name, message, exclude_user ? nickname : nil)
        end
      end

      def notify_user_parted(nickname : String, channel_name : String, reason : String? = nil)
        if user = @user_repository.get(nickname)
          message = String.build do |io|
            io << ':' << user.hostmask << " PART " << channel_name
            io << " :" << reason if reason
          end

          send_to_channel_members(channel_name, message)
        end
      end

      def notify_user_quit(nickname : String, reason : String? = nil)
        if user = @user_repository.get(nickname)
          message = String.build do |io|
            io << ':' << user.hostmask << " QUIT"
            io << " :" << reason if reason
          end

          send_to_shared_channel_members(nickname, message)
        end
      end

      def notify_nick_change(old_nickname : String, new_nickname : String)
        if user = @user_repository.get(new_nickname) # User already updated in repository
          message = ":#{old_nickname}!#{user.username}@#{user.hostname} NICK #{new_nickname}"
          send_to_shared_channel_members(new_nickname, message)
        end
      end

      def notify_topic_change(channel_name : String, topic : String, set_by : String)
        if user = @user_repository.get(set_by)
          message = ":#{user.hostmask} TOPIC #{channel_name} :#{topic}"
          send_to_channel_members(channel_name, message)
        end
      end

      def notify_mode_change(channel_name : String, modes : String, set_by : String, targets : Array(String) = [] of String)
        if user = @user_repository.get(set_by)
          message = String.build do |io|
            io << ':' << user.hostmask << " MODE " << channel_name << ' ' << modes
            targets.each do |target|
              io << ' ' << target
            end
          end

          send_to_channel_members(channel_name, message)
        end
      end

      def notify_user_kicked(channel_name : String, kicked_user : String, kicker : String, reason : String? = nil)
        if user = @user_repository.get(kicker)
          message = String.build do |io|
            io << ':' << user.hostmask << " KICK " << channel_name << ' ' << kicked_user
            io << " :" << reason if reason
          end

          send_to_channel_members(channel_name, message)
        end
      end

      def notify_invite(inviter : String, invited : String, channel_name : String)
        if user = @user_repository.get(inviter)
          message = ":#{user.hostmask} INVITE #{invited} #{channel_name}"

          # Send to invited user if they're local
          if client = @user_repository.get_client(invited)
            client.send_message(message)
          end
        end
      end

      def notify_channel_message(sender : String, channel_name : String, message_text : String)
        if user = @user_repository.get(sender)
          message = ":#{user.hostmask} PRIVMSG #{channel_name} :#{message_text}"
          send_to_channel_members(channel_name, message, sender)
        end
      end

      def notify_private_message(sender : String, target : String, message_text : String)
        if user = @user_repository.get(sender)
          message = ":#{user.hostmask} PRIVMSG #{target} :#{message_text}"

          if client = @user_repository.get_client(target)
            client.send_message(message)
          end
        end
      end

      def notify_channel_notice(sender : String, channel_name : String, message_text : String)
        if user = @user_repository.get(sender)
          message = ":#{user.hostmask} NOTICE #{channel_name} :#{message_text}"
          send_to_channel_members(channel_name, message, sender)
        end
      end

      def notify_private_notice(sender : String, target : String, message_text : String)
        if user = @user_repository.get(sender)
          message = ":#{user.hostmask} NOTICE #{target} :#{message_text}"

          if client = @user_repository.get_client(target)
            client.send_message(message)
          end
        end
      end

      def notify_netsplit(affected_users : Array(Domain::User), reason : String)
        affected_users.each do |user|
          quit_message = ":#{user.hostmask} QUIT :#{reason}"
          send_to_shared_channel_members(user.nickname, quit_message)
        end
      end

      def notify_server_message(server_name : String, message : String)
        # Send server notice to all local users
        server_message = ":#{server_name} NOTICE * :#{message}"

        @user_repository.find_local_users.each do |user|
          if client = @user_repository.get_client(user.nickname)
            client.send_message(server_message)
          end
        end
      end

      # Remote user notifications (from other servers)
      def notify_remote_user_joined(nickname : String, username : String, hostname : String, channel_name : String)
        hostmask = "#{nickname}!#{username}@#{hostname}"
        message = ":#{hostmask} JOIN #{channel_name}"
        send_to_channel_members(channel_name, message, nickname)
      end

      def notify_remote_user_parted(nickname : String, username : String, hostname : String,
                                    channel_name : String, reason : String? = nil)
        hostmask = "#{nickname}!#{username}@#{hostname}"
        message = String.build do |io|
          io << ':' << hostmask << " PART " << channel_name
          io << " :" << reason if reason
        end

        send_to_channel_members(channel_name, message)
      end

      def notify_remote_user_quit(nickname : String, username : String, hostname : String, reason : String? = nil)
        hostmask = "#{nickname}!#{username}@#{hostname}"
        message = String.build do |io|
          io << ':' << hostmask << " QUIT"
          io << " :" << reason if reason
        end

        send_to_shared_channel_members(nickname, message)
      end

      def notify_quit_in_channels(nickname : String, channels : Array(Domain::Channel), message : String) : Nil
        notified_users = Set(String).new

        channels.each do |channel|
          channel.members.each_key do |member_nickname|
            next if member_nickname == nickname || notified_users.includes?(member_nickname)

            if (client = @user_repository.get_client(member_nickname)) && !client.closed?
              client.send_message(message)
              notified_users << member_nickname
            end
          end
        end
      end

      def notify_batch_join(channel_name : String, nicknames : Array(String))
        nicknames.each do |nickname|
          if user = @user_repository.get(nickname)
            message = ":#{user.hostmask} JOIN #{channel_name}"
            send_to_channel_members(channel_name, message, nickname)
          end
        end
      end

      private def send_to_channel_members(channel_name : String, message : String, exclude_nickname : String? = nil)
        if channel = @channel_repository.get(channel_name)
          channel.members.each_key do |nickname|
            next if exclude_nickname && nickname == exclude_nickname

            if client = @user_repository.get_client(nickname)
              client.send_message(message)
            end
          end
        end
      end

      private def send_to_shared_channel_members(nickname : String, message : String)
        # Find all channels the user was in and notify local members
        user_channels = @channel_repository.find_user_channels(nickname)
        notified_users = Set(String).new

        user_channels.each do |channel|
          channel.members.each_key do |member_nickname|
            next if notified_users.includes?(member_nickname)

            if client = @user_repository.get_client(member_nickname)
              client.send_message(message)
              notified_users << member_nickname
            end
          end
        end
      end
    end
  end
end
