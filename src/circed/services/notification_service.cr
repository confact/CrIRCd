# Service for handling user notifications and event broadcasting
module Circed
  module Services
    class NotificationService
      def initialize(@user_repository : Repositories::UserRepository,
                     @channel_repository : Repositories::ChannelRepository)
      end

      def notify_channel(channel : Domain::Channel, message : String, exclude_nickname : String? = nil)
        channel.members.each_key do |nickname|
          next if exclude_nickname && Domain::CaseMapping.same?(nickname, exclude_nickname)

          @user_repository.get_client(nickname).try(&.send_message(message))
        end
      end

      def notify_channel(channel_name : String, message : String, exclude_nickname : String? = nil)
        @channel_repository[channel_name]?.try do |channel|
          notify_channel(channel, message, exclude_nickname)
        end
      end

      def notify_user(nickname : String, message : String)
        @user_repository.get_client(nickname).try(&.send_message(message))
      end

      def notify_shared_channels(nickname : String, message : String)
        notified_users = Set(String).new

        @channel_repository.each_user_channel(nickname) do |channel|
          channel.members.each_key do |member_nickname|
            next if Domain::CaseMapping.same?(member_nickname, nickname)

            if (client = @user_repository.get_client(member_nickname)) && notified_users.add?(member_nickname)
              client.send_message(message)
            end
          end
        end
      end

      def notify_channels(nickname : String, channels : Enumerable(Domain::Channel), message : String)
        notified_users = Set(String).new

        channels.each do |channel|
          channel.members.each_key do |member_nickname|
            next if Domain::CaseMapping.same?(member_nickname, nickname)

            if (client = @user_repository.get_client(member_nickname)) && !client.closed? && notified_users.add?(member_nickname)
              client.send_message(message)
            end
          end
        end
      end
    end
  end
end
