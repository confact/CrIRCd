module Circed
  module ActionHelper

    def parse(sender : Client, message, io : IO)
      prefix = FastIRC::Prefix.new(source: sender.nickname.to_s, user: sender_user(sender), host: sender_host(sender))
      text = String.build do |io|
        FastIRC::Message.new(@@command, message, prefix: prefix).to_s(io)
      end
      Log.debug { "Parsed: #{text}" }
      FastIRC::Message.new(@@command, message, prefix: prefix).to_s(io)
    end

    def parse(sender : Client, receiver, message, io : IO)
      prefix = FastIRC::Prefix.new(source: sender.nickname.to_s, user: sender_user(sender), host: sender_host(sender))
      text = String.build do |io|
        FastIRC::Message.new(@@command, [receiver, message], prefix: prefix).to_s(io)
      end
      Log.debug { "Parsed: #{text}" }
      FastIRC::Message.new(@@command, [receiver, message], prefix: prefix).to_s(io)
    end

    def send_to_channel(channel : String, &block)
      channel = ChannelHandler.get_channel(channel)
      Log.debug { "Sending to channel #{channel.name}" }
      channel.users.each do |user|
        yield user.client, user.client.socket if user.client.try(&.socket)
      end
    end

    def send_to_channel(channel : Channel, &block)
      Log.debug { "Sending to channel #{channel.name}" }
      channel.users.each do |user|
        yield user.client, user.client.socket if user.client.try(&.socket)
      end
    end

    def send_to_user_channel(user : Client, &block)
      channels = ChannelHandler.user_channels(user)
      channels.each do |channel|
        channel.users.each do |channel_user|
          yield channel_user.client, channel_user.client.socket if channel_user.client.try(&.socket)
        end
      end
    end

    def send_to_user(user_name : String, &block)
      client = UserHandler.get_client(user_name)
      yield client, client.try(&.socket) if client.try(&.socket)
    end

    def send_to_user(user : Client, &block)
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
