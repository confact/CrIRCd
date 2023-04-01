module Circed
  class ChannelHandler
    @@channels : Hash(String, Channel) = {} of String => Channel

    def self.channels
      @@channels
    end
    def self.clear
      @@channels.clear
    end

    def self.add_user_to_channel(channel : String, client : Client)
      add_channel(channel)

      @@channels[channel].add_client(client)
    end

    def self.add_channel(channel : String) : Channel
      if @@channels[channel]? == nil
        @@channels[channel] = Channel.new(channel)
      end

      @@channels[channel]
    end

    def self.add_channel(channel : Channel) : Channel
      @@channels[channel.name] = channel
    end

    def self.remove_user_from_channel(channel : String, client : Client)
      if @@channels[channel]? != nil
        @@channels[channel].remove_client(client)
        if @@channels[channel].channel_empty?
          @@channels.delete(channel)
        end
      end
    end

    def self.remove_user_from_all_channels(client : Client)
      @@channels.each do |_channel, channel_obj|
        channel_obj.remove_client(client)
        if channel_obj.channel_empty?
          @@channels.delete(channel_obj)
        end
      end
    end

    def self.send_to_all_channels(client : Client, *args)
      @@channels.each do |_channel, channel_obj|
        channel_obj.send_raw(client, *args)
      end
    end

    def self.get_channel(channel : String)
      @@channels[channel]?
    end

    def self.channel_is_full?(channel : String)
      if @@channels[channel]? != nil
        return @@channels[channel].channel_full?
      end
      false
    end

    def self.user_channels(client : Client)
      @@channels.select { |_channel, channel_obj| channel_obj.user_in_channel?(client) }.values
    end

    def self.channel_empty?(channel : String)
      if @@channels[channel]? != nil
        @@channels[channel].channel_empty?
      else
        true
      end
    end

    def self.channel_exists?(channel : String)
      if @@channels[channel]? != nil
        true
      else
        false
      end
    end

    def self.size
      @@channels.size
    end

    def self.channel_list
      @@channels.keys
    end

    def self.channel_is_private?(channel : String) : Bool
      if @@channels[channel]? != nil
        @@channels[channel].private?
      else
        false
      end
    end

    def self.channel_has_password?(channel : String) : Bool
      if @@channels[channel]? != nil
        @@channels[channel].channel_password != nil
      else
        false
      end
    end

    def self.channel_password(channel : String) : String?
      if @@channels[channel]? != nil
        @@channels[channel].channel_password
      else
        nil
      end
    end

    def self.change_mode(channel : String, mode : String, client : Client)
      if @@channels[channel]?
        @@channels[channel].change_mode(mode, client)
      end
    end

    def self.user_in_channel?(channel : String, client : Client)
      if @@channels[channel]?
        @@channels[channel].user_in_channel?(client)
      else
        false
      end
    end
  end
end
