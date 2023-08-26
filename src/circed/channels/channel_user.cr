module Circed
  class ChannelUser
    getter client : Client
    getter channel : Channel

    getter modes : UserMode

    def initialize(client, channel)
      @client = client
      @channel = channel
      @modes = UserMode.new
    end

    def add_mode(mode : String)
      @modes.add(mode)
    end

    def remove_mode(mode : String)
      @modes.remove(mode)
    end

    def to_s
      String.build do |io|
        io << modes.highest_mode
        io << client.nickname
      end
    end

    def nickname
      client.nickname
    end

    def hostmask
      client.hostmask || ""
    end

    def mode_string
      modes.to_s
    end

    def is_operator?
      modes.is_operator?
    end

    def is_half_operator?
      modes.is_half_operator?
    end

    def is_voiced?
      modes.is_voiced?
    end

    def send_message_to_server(*args)
      client.send_message_to_server(*args)
    end

    def send_message_to_receiver(*args)
      client.send_message_to_receiver(*args)
    end
  end
end
