module Circed
  class ChannelHandler
    @@channels : Hash(String, Channel) = {} of String => Channel



    def self.add_user_to_channel(channel : String, client : Client)
      if @@channels[channel]? == nil
        @@channels[channel] = Channel.new(channel)
      end

      @@channels[channel].add_client(client)
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
      @@channels.each do |channel, channel_obj|
        channel_obj.remove_client(client)
        if channel_obj.channel_empty?
          @@channels.delete(channel)
        end
      end
    end

    def self.send_to_all_channels(client : Client, *args)
      @@channels.each do |channel, channel_obj|
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
      chs = [] of Channel
      @@channels.each do |channel, channel_obj|
        if channel_obj.user_in_channel?(client)
          chs << channel
        end
      end
      chs
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
