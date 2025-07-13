module Circed
  module ActionHelper
    macro extended
      COMMAND = {{@type.name.split("::").last.upcase}}

      def self.command
        {{@type.name}}::COMMAND
      end
    end

    def parse(sender : Client, message, io : IO)
      prefix = FastIRC::Prefix.new(source: sender.nickname.to_s, user: sender_user(sender), host: sender_host(sender))
      text = String.build do |io|
        FastIRC::Message.new(command, message, prefix: prefix).to_s(io)
      end
      Log.debug { "Parsed: #{text}" }
      FastIRC::Message.new(command, message, prefix: prefix).to_s(io)
    end

    def parse(sender : Client, receiver, message, io : IO)
      prefix = FastIRC::Prefix.new(source: sender.nickname.to_s, user: sender_user(sender), host: sender_host(sender))
      text = String.build do |io|
        FastIRC::Message.new(command, [receiver, message], prefix: prefix).to_s(io)
      end
      Log.debug { "Parsed: #{text}" }
      FastIRC::Message.new(command, [receiver, message], prefix: prefix).to_s(io)
    end

    def send_to_channel(channel_name : String, &block)
      channel_repository = Infrastructure::ServiceLocator.channel_repository
      if channel = channel_repository.get(channel_name)
        send_to_channel(channel, &block)
      end
    end

    def send_to_channel(channel : Domain::Channel, &)
      Log.debug { "Sending to channel #{channel.name}" }
      user_repo = Infrastructure::ServiceLocator.user_repository

      channel.members.keys.each do |nickname|
        if client = user_repo.get_client(nickname)
          yield client, client.socket if client.socket
        end
      end
    end

    def send_to_user_channel(user : Client, &)
      return unless nickname = user.nickname

      channel_repository = Infrastructure::ServiceLocator.channel_repository
      channels = channel_repository.find_user_channels(nickname)
      user_repo = Infrastructure::ServiceLocator.user_repository

      channels.each do |channel|
        channel.members.keys.each do |member_nickname|
          if client = user_repo.get_client(member_nickname)
            yield client, client.socket if client.socket
          end
        end
      end
    end

    def send_to_user(user_name : String, &)
      user_repository = Infrastructure::ServiceLocator.user_repository
      client = user_repository.get_client(user_name)
      yield client, client.try(&.socket) if client.try(&.socket)
    end

    def send_to_user(user : Client, &)
      yield user, user.try(&.socket) if user.try(&.socket)
    end

    def sender_user(sender)
      sender.user.try(&.name)
    end

    def sender_host(sender)
      sender.host
    end

    def send_error(sender, code, message : String)
      sender.send_message(Server.clean_name, code, sender.nickname, ":#{message}")
    end

    def send_error(sender, code, item : String, message : String)
      sender.send_message(Server.clean_name, code, sender.nickname, item, ":#{message}")
    end
  end
end
