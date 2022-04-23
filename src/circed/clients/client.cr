require "tasker"

module Circed
  class Client

    getter socket : TCPSocket?
    getter host : String?
    getter nickname : String?

    getter user : User?

    @pingpong : Pingpong?

    def initialize(@socket : Socket?)
      @host = @socket.try(&.remote_address.to_s)
    end

    def setup
      message_handling
    end

    def message_handling
      while data_line = socket.try(&.gets)
        message = IO::Memory.new(data_line)
        FastIRC.parse(message) do |payload|
          case payload.command
          when "NICK"
            set_nickname(payload.params.first)
          when "USER"
            set_user(payload.params)
          when "PONG"
            pong(payload.params)
          when "PING"
            ping(payload.params)
          when "JOIN"
            next if payload.params.empty?
            join_channel(payload.params.first)
          when "PART"
            part_channel(payload.params.first)
          when "MODE"
            mode(payload.params)
          when "QUIT"
            quit(payload.params)
          when "KICK"
            kick(payload.params)
          when "TOPIC"
            topic(payload.params)
          when "INVITE"
            invite(payload.params)
          when "NOTICE"
            notice(payload.params)
          when "PRIVMSG"
            private_message(payload.params.first, payload.params[1..-1].join)
          end
        end

        if closed?
          UserHandler.remove_connection(nickname.to_s) unless nickname.to_s.empty?
          break
        end
      end
    rescue e : IO::Error
      shutdown
      UserHandler.remove_connection(nickname.to_s) unless nickname.to_s.empty?
    rescue e : Circed::ClosedClient
      UserHandler.remove_connection(nickname.to_s) unless nickname.to_s.empty?
    rescue e : Exception
      shutdown
      UserHandler.remove_connection(nickname.to_s) unless nickname.to_s.empty?
    end

    def set_nickname(new_nickname)
      if UserHandler.nickname_used?(new_nickname)
        send_message(Server.clean_name, Numerics::ERR_NICKNAMEINUSE, new_nickname, ":Nickname is already in used")
        return
      end
      changed = !nickname.to_s.empty?
      old_nickname = nickname

      if changed
        begin
          Log.debug { "changing nickname to: #{new_nickname} " }
          UserHandler.changed_nickname(old_nickname.to_s, new_nickname)
          send_message_to_server("NICK", old_nickname.to_s, user.not_nil!.name, host.not_nil!, new_nickname.split)
          @nickname = new_nickname
          ChannelHandler.send_to_all_channels(self, "NICK", old_nickname.to_s, user.not_nil!.name, host.not_nil!, new_nickname.split)
        rescue e : Exception
          Log.debug { "error, nickname is not used: #{nickname} " }
          @nickname = old_nickname
          send_message(Server.clean_name, Numerics::ERR_ERRONEUSNICKNAME, old_nickname, ":Nickname is not used.")
        end
      else
        Log.debug { "Set nickname to: #{new_nickname} " }
        @nickname = new_nickname
        send_message(Server.clean_name, "NICK", new_nickname)
      end
    end

    def set_user(users_messages : Array(String))
      mode = users_messages[1]
      username = users_messages.first
      realname = users_messages[3].sub(":", "")
      @user = User.new(self, mode, username, realname)
      Log.debug { "Set user to: #{user.to_s}" }
      Circed::Server.welcome_message(self)
      @pingpong = Pingpong.new(self)
    end

    def private_message(receiver : String, message : String)
      if receiver.starts_with?("#")
        channel = ChannelHandler.get_channel(receiver)
        if channel
          channel.send_message(self, message)
        else
          send_message(Server.clean_name, Numerics::ERR_NOSUCHCHANNEL, receiver, ":No such channel")
        end
      else
        client = UserHandler.get_client(receiver)
        if client
          client.not_nil!.send_message_to_receiver("PRIVMSG", nickname.not_nil!, user.not_nil!.name, host.not_nil!, message.split)
        else
          send_message(Server.clean_name, Numerics::ERR_NOSUCHNICK, receiver, ":No such nick")
        end
      end
    end

    def join_channel(channel : String)
      channels = channel.split(",")
      channels.each do |ch|
        ch = ch.strip
        if ch.empty?
          send_message(Server.clean_name, Numerics::ERR_NOSUCHCHANNEL, ch, ":No such channel")
          next
        end
        if ChannelHandler.channel_is_full?(ch)
          send_message(Server.clean_name, Numerics::ERR_CHANNELISFULL, ch, ":Channel is full")
          next
        end
        if ChannelHandler.user_in_channel?(ch, self)
          send_message(Server.clean_name, Numerics::ERR_USERONCHANNEL, ch, ":User is already in channel")
          next
        end
        ChannelHandler.add_user_to_channel(ch, self)
        #send_message(Server.clean_name, "JOIN", channel)
      end
    end

    def part_channel(channel : String)
      channels = channel.split(",")
      channels.each do |ch|
        ch = ch.strip
        if ch.empty?
          send_message(Server.clean_name, Numerics::ERR_NOSUCHCHANNEL, ch, ":No such channel")
          next
        end
        if !ChannelHandler.channel_exists?(ch)
          send_message(Server.clean_name, Numerics::ERR_NOSUCHCHANNEL, ch, ":No such channel")
          next
        end
        if !ChannelHandler.user_in_channel?(ch, self)
          send_message(Server.clean_name, Numerics::ERR_NOTONCHANNEL, ch, ":User is not in channel")
          next
        end
        ChannelHandler.remove_user_from_channel(ch, self)
        #send_message(Server.clean_name, "PART", channel)
      end
    end

    def quit(_message)
      shutdown
      close
    end

    def send_message(message)
      Log.info { message }
      if closed?
        Log.debug { "Socket is closed, can't send message" }
        return
      end
      socket.try(&.puts(message + "\n"))
    end

    def notice(message)
      send_message(":#{message}")
    end

    def mode(message)
      user_or_channel = message.first
      if user_or_channel.starts_with?("#")
        channel = ChannelHandler.get_channel(user_or_channel)
        if channel
          channel.change_channel_mode(self, message[1..-1].join)
        else
          send_message(Server.clean_name, Numerics::ERR_NOSUCHCHANNEL, user_or_channel, ":No such channel")
        end
      else
        client = UserHandler.get_client(user_or_channel)
        if client
          #client.not_nil!.mode(self, message[1..-1].join)
        else
          send_message(Server.clean_name, Numerics::ERR_NOSUCHNICK, user_or_channel, ":No such nick")
        end
      end
    end

    def topic(message)
      channel = message.first
      if channel.starts_with?("#")
        if ChannelHandler.channel_exists?(channel)
          ChannelHandler.get_channel(channel).try(&.set_topic(self, message[1..-1].join))
        else
          send_message(Server.clean_name, Numerics::ERR_NOSUCHCHANNEL, channel, ":No such channel")
        end
      else
        send_message(Server.clean_name, Numerics::ERR_BADCHANMASK, channel, ":Wrong channel format")
      end
    end

    def kick(message)
      Log.debug { "kick: #{message}" }
      channel = message.first
      if channel.starts_with?("#")
        if ChannelHandler.channel_exists?(channel)
          ChannelHandler.get_channel(channel).try(&.kick(self, message[1], message[2..-1].join))
        else
          send_message(Server.clean_name, Numerics::ERR_NOSUCHCHANNEL, channel, ":No such channel")
        end
      else
        send_message(Server.clean_name, Numerics::ERR_BADCHANMASK, channel, ":Wrong channel format")
      end
    end

    def invite(message)
      channel = message.first
      if channel.starts_with?("#")
        if ChannelHandler.channel_exists?(channel)
          #ChannelHandler.get_channel(channel).invite(self, message[1..-1].join)
        else
          send_message(Server.clean_name, Numerics::ERR_NOSUCHCHANNEL, channel, ":No such channel")
        end
      else
        send_message(Server.clean_name, Numerics::ERR_BADCHANMASK, channel, ":Wrong channel format")
      end
    end

    def send_message(prefix, command, *params)
      if closed?
        Log.debug { "Socket is closed, can't send message" }
        return
      end
      message = "#{prefix} #{command} #{params.join(" ")}\n"
      Log.info { message }
      socket.try(&.puts(message))
    end

    def send_message_to_receiver(command, sender_nickname, sender_user, sender_host, params : Array(String))
      prefix = FastIRC::Prefix.new(source: sender_nickname, user: sender_user, host: sender_host)
      message = String.build do |io|
        FastIRC::Message.new(command, [user.not_nil!.name] + params, prefix: prefix).to_s(io)
      end
      Log.debug { "sending message to #{sender_nickname}: #{message}" }
      Log.info { message }
      if closed?
        Log.debug { "Socket is closed, can't send message" }
        return
      end
      socket.try(&.puts(message))
    end

    def send_message_to_server(command, sender_nickname, sender_user, sender_host, params : Array(String))
      prefix = FastIRC::Prefix.new(source: sender_nickname, user: sender_user, host: sender_host)
      message = String.build do |io|
        FastIRC::Message.new(command, params, prefix: prefix).to_s(io)
      end
      Log.debug { "sending message to #{sender_nickname}: #{message}" }
      Log.info { message }
      socket.try(&.puts(message))
    end

    def close
      Log.info { "Closing connection" }
      socket.try(&.close)
      raise ClosedClient.new("closed")
    end

    def closed? : Bool
      socket.try(&.closed?) || false
    end

    def pong(params : Array(String))
      @pingpong.try(&.pong(params))
      Log.debug { "PONG #{@nickname}" }
      #send_message("PING :#{@nickname} :localhost")
    end

    def ping(params : Array(String))
      @pingpong.try(&.ping(params))
      #return if @last_checked && @last_checked.not_nil! < 5.seconds.ago
    end

    def shutdown
      ChannelHandler.remove_user_from_all_channels(self)
      if @pingpong
        @pingpong.try(&.stop_ping)
        @pingpong.try(&.stop_pong_check)
      end
      socket.try(&.close)
    end
  end
end
