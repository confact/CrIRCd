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

    def set_mode(mode : String)
      if mode.starts_with?("+")
        @user_mode.add(mode.lchop)
      elsif mode.starts_with?("-")
        @user_mode.remove(mode.lchop)
      end
    rescue e : Exception
      client.send_message(Server.clean_name, Numerics::ERR_UMODEUNKNOWNFLAG, ":Unknown user mode flag: #{mode}")
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

    def mode_string
      user_mode.to_s
    end

    def is_operator?
      user_mode.is_operator?
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
