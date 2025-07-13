module Circed
  class ServerHandler
    @@servers : Set(LinkServer) = Set(LinkServer).new

    def self.add_server(server)
      @@servers.add(server)
    end

    def self.remove_server(server)
      @@servers.delete(server)
    end

    def self.servers
      @@servers
    end

    def self.handle_message(message)
      @@servers.each do |server|
        server.handle_message(message)
      end
    end
  end
end
