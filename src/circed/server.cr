require "socket"
require "yaml"
require "watcher"

module Circed
  class ClosedClient < Exception; end
  class Server
    class_getter config = Config.from_yaml(File.read("config.yml"))
    @@config_cache : String = File.read("config.yml")

    # @@servers

    def self.start
      watch_config_file
      server = TCPServer.new(config.host, config.port)
      # @@address = server.local_address.to_s
      start_message
      loop do
        if client = server.accept?
          # handle the client in a fiber
          Log.info { "new user! - #{client.remote_address}" }
          spawn handle_client(client)
        else
          # another fiber closed the server
          break
        end
      end
    end

    def self.handle_client(client)
      if UserHandler.size >= config.max_users
        Log.warn { "User limit reached, refusing new client: #{client.remote_address}" }
        client.puts "ERROR :Closing Link: #{client.remote_address} (Max users limit reached)"
        sleep 1
        client.close
        return
      end

      new_client = Circed::Client.new(client)
      Log.debug { "new client: #{new_client.inspect}" }
      new_client.setup
      # new_client.send_message(motd)
    end

    def bootup_servers
    end

    def self.created
      @@config.created
    end

    def self.welcome_message(client : Client)
      nick = client.nickname.to_s
      UserHandler.add_client(client)
      Log.info { "Sends welcome to #{nick}" }
      client.send_message(clean_name, Numerics::RPL_WELCOME, nick, ":Welcome to the Internet Relay Network #{nick}!")
      client.send_message(clean_name, Numerics::RPL_YOURHOST, nick, ":Your host is #{@@config.host}, running version Circed #{VERSION}")
      client.send_message(clean_name, Numerics::RPL_CREATED, nick, ":This server was created #{Server.created}")
      client.send_message(clean_name, Numerics::RPL_MYINFO, nick, "#{Server.name} #{config.network}", "Circed", "o o o")
      client.send_message(clean_name, Numerics::RPL_ISUPPORT, nick, ":CASEMAPPING=ascii", "are supported by this server")
      client.send_message(clean_name, Numerics::RPL_ISUPPORT, nick, ":PREFIX=(ohv)@%+", "are supported by this server")
      data = ""
      data += lusers(client)
      data += motd(client)
      client.send_message(data)
    end

    def self.lusers(client : Client)
      nick = client.nickname
      data = ""
      data += Format.format_server_message(name, Numerics::RPL_LUSERCLIENT, nick, ":There are #{UserHandler.size} users and 0 invisible on 1 server(s)")
      data += Format.format_server_message(name, Numerics::RPL_LUSEROP, nick, ":1 IRC Operators online")
      data += Format.format_server_message(name, Numerics::RPL_LUSERUNKNOWN, nick, ":0 unregistered connections")
      data += Format.format_server_message(name, Numerics::RPL_LUSERCHANNELS, nick, ":#{ChannelHandler.size} channels formed")
      data += Format.format_server_message(name, Numerics::RPL_LUSERME, nick, ":I have #{UserHandler.size} clients and 1 servers")
      data += Format.format_server_message(name, Numerics::RPL_LOCALUSERS, nick, UserHandler.size, config.max_users, ":Current local users #{UserHandler.size}, max #{config.max_users}")
      data += Format.format_server_message(name, Numerics::RPL_GLOBALUSERS, nick, UserHandler.size, config.max_users, ":Current global users #{UserHandler.size}, max #{config.max_users}")
      data
    end

    def self.start_message
      puts " Circed #{VERSION}"
      puts " Running on #{config.host}:#{config.port}"
      puts " ---"
    end

    def self.address
      ":" + config.host
    end

    def self.motd(client : Client)
      text = <<-TEXT
        Welcome to Circd Server
      TEXT
      motd = text.split("\n")
      data = ""
      data += Format.format_server_message(name, Numerics::RPL_MOTDSTART, client.nickname, ":- localhost Message of the day - ")
      motd.each do |line|
        data += Format.format_server_message(name, Numerics::RPL_MOTD, client.nickname, line)
      end
      data += Format.format_server_message(name, Numerics::RPL_ENDOFMOTD, client.nickname, "End of MOTD command")
      data
    end

    def self.clean_name
      ":" + config.host
    end

    def self.name
      config.host
    end

    def self.watch_config_file
      spawn do
        watch "config.yml", 2 do |event|
          event.on_change do
            file_content = File.read("config.yml")
            if @@config_cache != file_content
              Log.info { "config.yml changed, reloading" }
              @@config_cache = file_content
              @@config = Config.from_yaml(file_content)
            end
          end
        end
      end
    end
  end
end
