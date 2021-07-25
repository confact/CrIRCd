require "socket"

module Circed
  class Server
    class NicknameUsedError < Exception; end
    class NicknameNoUsedError < Exception; end

    @@connections : Hash(String, Circed::Client) = {} of String => Circed::Client

    @@name = "localhost"
    @@created = Time.utc
    @@address = "::1"

    # @@servers

    def self.start
      server = TCPServer.new("localhost", 6667)
      # @@address = server.local_address.to_s
      start_message
      while client = server.accept?
        Log.info { "new user! - #{client.remote_address}" }
        spawn handle_client(client)
      end
    end

    def self.handle_client(client)
      new_client = Circed::Client.new(client)
      new_client.setup
      # new_client.send_message(motd)
    end

    def bootup_servers
    end

    def self.welcome_message(client : Client)
      nick = client.nickname.to_s
      add_connections(client)
      Log.info { "Sends welcome to #{nick}" }
      client.send_message(":localhost", Numerics::RPL_WELCOME, nick, ":Welcome to the Internet Relay Network #{nick}")
      client.send_message(":localhost", Numerics::RPL_YOURHOST, nick, ":Your host is #{@@address}, running version Circed #{VERSION}")
      client.send_message(":localhost", Numerics::RPL_CREATED, nick, ":This server was created #{Server.created}")
      client.send_message(":localhost", Numerics::RPL_MYINFO, nick, @@name, "Circed", "o o o")
      client.send_message(":localhost", Numerics::RPL_ISUPPORT, nick, ":CASEMAPPING=ascii", "are supported by this server")
      data = ""
      data += lusers(client)
      data += motd(client)
      client.send_message(data)
    end

    private def self.add_connections(client : Client)
      nick = client.nickname.to_s
      @@connections[nick] = client
    end

    def self.changed_nickname(old_nickname : String, new_nickname : String)
      client = @@connections[old_nickname]?
      raise NicknameNoUsedError.new if client.nil?
      if client
        @@connections[new_nickname] = client
        @@connections.delete(old_nickname)
      end
    end

    def self.client_exists?(nickname : String)
      !@@connections[nickname]?.nil?
    end

    alias_method :nickname_used?, :client_exists?

    def self.remove_connection(nickname : String)
      @@connections.delete(nickname)
    end

    def self.get_client(nickname : String)
      @@connections[nickname]?
    end

    def self.lusers(client : Client)
      nick = client.nickname
      data = ""
      data += Format.format_server_message("localhost", Numerics::RPL_LUSERCLIENT, nick, ":There are #{@@connections.size} users and 0 invisible on 1 server(s)")
      data += Format.format_server_message("localhost", Numerics::RPL_LUSEROP, nick, ":1 IRC Operators online")
      data += Format.format_server_message("localhost", Numerics::RPL_LUSERUNKNOWN, nick, ":0 unregistered connections")
      data += Format.format_server_message("localhost", Numerics::RPL_LUSERCHANNELS, nick, ":0 channels formed")
      data += Format.format_server_message("localhost", Numerics::RPL_LUSERME, nick, ":I have #{@@connections.size} clients and 1 servers")
      data += Format.format_server_message("localhost", Numerics::RPL_LOCALUSERS, nick, @@connections.size, 10000, ":Current local users #{@@connections.size}, max 10000")
      data += Format.format_server_message("localhost", Numerics::RPL_GLOBALUSERS, nick, @@connections.size, 10000, ":Current global users #{@@connections.size}, max 10000")
      data
    end

    def self.start_message
      puts " Circed #{VERSION}"
      puts " Running on #{@@address}"
      puts " ---"
    end

    def self.name
      ":" + @@address
    end

    def self.created
      @@created
    end

    def self.motd(client : Client)
      text = <<-TEXT
        Welcome to Circd Server
      TEXT
      motd = text.split("\n")
      data = ""
      data += Format.format_user_message(Numerics::RPL_MOTDSTART, client.nickname, ":- localhost Message of the day - ")
      motd.each do |line|
        data += Format.format_user_message(Numerics::RPL_MOTD, client.nickname, line)
      end
      data += Format.format_user_message(Numerics::RPL_ENDOFMOTD, client.nickname, "End of MOTD command")
      data
    end
  end
end
