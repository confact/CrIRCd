module Circed
  class ChannelUser
    getter client : Client
    getter channel : Channel

    getter user_mode : UserMode

    def initialize(client, channel)
      @client = client
      @channel = channel
      @user_mode = UserMode.new
    end

    def add_mode(mode : String)
      @user_mode.add(mode)
    end

    def remove_mode(mode : String)
      @user_mode.remove(mode)
    end

    def to_s
      String.build do |io|
        io << user_mode.highest_mode
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
      user_mode.to_s
    end

    def is_operator?
      user_mode.is_operator?
    end

    def is_half_operator?
      user_mode.is_half_operator?
    end

    def is_voiced?
      user_mode.is_voiced?
    end

    def send_message_to_server(*args)
      client.send_message_to_server(*args)
    end

    def send_message_to_receiver(*args)
      client.send_message_to_receiver(*args)
    end
  end
end
