require "socket"
module Circed
  class Server

    @@connections : Array(Circed::Client) = [] of Client

    @@name = "localhost"
    @@created = Time.utc
    @@address = "::1"

    # @@servers

    def self.start
      server = TCPServer.new("localhost", 6667)
      #@@address = server.local_address.to_s
      start_message
      while client = server.accept?
        Log.info { "new user! - #{client.remote_address}" }
        spawn handle_client(client)
      end
    end

    def self.handle_client(client)
      new_client = Circed::Client.new(client)
      @@connections << new_client
      new_client.setup
      #new_client.send_message(motd)
    rescue e : Client::ClosedClient
      @@connections.delete(new_client) if client && client.closed?
    end

    def bootup_servers

    end

    def self.welcome_message(client : Client)
      nick = client.nickname
      Log.info { "Sends welcome to #{nick}" }
      client.send_message(@@name, Numerics::RPL_WELCOME, ":Welcome to the Internet Relay Network #{client.nickname}")
      client.send_message(@@name, Numerics::RPL_YOURHOST, nick, ":Your host is #{@@address}, running version Circed #{VERSION}")
      client.send_message(@@name, Numerics::RPL_CREATED, nick, ":This server was created #{Server.created}")
      client.send_message(@@name, Numerics::RPL_MYINFO, nick, @@name, "Circed", "o o o")
      client.send_message(@@name, Numerics::RPL_ISUPPORT, nick, ":CASEMAPPING=ascii", "are supported by this server")
      lusers(client)
      motd(client)
      #client.send_message(@@name, Numerics::RPL_ISUPPORT, nick, "CASEMAPPING=ascii are supported by this server")
      #client.send_message(@@name, Numerics::ERR_NOMOTD, nick, "MOTD is unavailable")
      #client.send_message(@@name, "NOTICE", nick, ":please register.")
    end

    def self.lusers(client : Client)
      nick = client.nickname
      client.send_message(@@name, Numerics::RPL_LUSERCLIENT, nick, ":There are 1 users and 0 invisible on 1 server(s)")
      client.send_message(@@name, Numerics::RPL_LUSEROP, nick, ":1 IRC Operators online")
      client.send_message(@@name, Numerics::RPL_LUSERUNKNOWN, nick, ":0 unregistered connections")
      client.send_message(@@name, Numerics::RPL_LUSERCHANNELS, nick, ":0 channels formed")
      client.send_message(@@name, Numerics::RPL_LUSERME, nick, ":I have 1 clients and 1 servers")
      client.send_message(@@name, Numerics::RPL_LOCALUSERS, nick, 1, 10000, ":Current local users 1, max 10000")
      client.send_message(@@name, Numerics::RPL_GLOBALUSERS, nick, 1, 10000, ":Current global users 1, max 10000")
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
      client.send_message(@@name, Numerics::RPL_MOTDSTART, client.nickname, ":- localhost Message of the day - ")
      motd.each do |line|
        client.send_message(@@name, Numerics::RPL_MOTD, client.nickname, line)
      end
      client.send_message(@@name, Numerics::RPL_ENDOFMOTD, client.nickname, "End of MOTD command")
    end
  end
end
