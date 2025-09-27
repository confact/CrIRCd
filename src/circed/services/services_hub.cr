require "./network_sync"

module Circed::Services
  # Central services hub - designates one server as the services server
  class ServicesHub
    @@services_server : String?
    @@is_services_server : Bool = false

    # Configure this server as the services server
    def self.become_services_server
      @@is_services_server = true
      @@services_server = Server.config.host
      Log.info { "This server is now the services server" }

      # Initialize services
      ServicesManager.setup("services.db")

      # Announce to network that we are the services server
      NetworkSync.broadcast_to_network("SERVICES #{Server.config.host}")
    end

    # Set which server in the network hosts services
    def self.services_server=(server_name : String)
      @@services_server = server_name
      @@is_services_server = (server_name == Server.config.host)

      if @@is_services_server
        Log.info { "We are the services server" }
      else
        Log.info { "Services server is: #{server_name}" }
      end
    end

    # Check if this server hosts services
    def self.services_server? : Bool
      @@is_services_server
    end

    # Get the services server name
    def self.services_server : String?
      @@services_server
    end

    # Route a services message to the appropriate server
    def self.route_services_message(sender_nick : String, target_service : String, message : String)
      if services_server?
        # Handle locally
        ServicesManager.handle_service_message(sender_nick, target_service, message)
      else
        # Forward to services server
        if services_server = @@services_server
          forward_to_services_server(sender_nick, target_service, message, services_server)
        else
          # No services server available
          if sender_client = Infrastructure::ServiceLocator.user_repository.get_client(sender_nick)
            sender_client.send_message(":#{target_service}!services@network NOTICE #{sender_nick} :Services are currently unavailable.")
          end
        end
      end
    end

    # Forward PRIVMSG to services server
    private def self.forward_to_services_server(sender_nick : String, target_service : String, message : String, services_server : String)
      # Find the route to services server
      route = find_route_to_server(services_server)
      if route_server = route
        server = ServerHandler.servers.find { |srv| srv.name == route_server }
        if server
          # Get sender's full hostmask for proper forwarding
          if sender_client = Infrastructure::ServiceLocator.user_repository.get_client(sender_nick)
            server.safe_send(":#{sender_client.hostmask} PRIVMSG #{target_service} :#{message}")
          end
        end
      end
    end

    # Find route to a specific server
    private def self.find_route_to_server(target_server : String) : String?
      # Use the network state to find routing
      Network::NetworkState.route_to_server(target_server)
    end

    # Handle services server announcements
    def self.handle_services_announcement(server_name : String)
      self.services_server = server_name

      # If we just learned about a services server, request sync
      unless services_server?
        NetworkSync.request_services_sync(server_name)
      end
    end

    # Handle server linking - sync services data
    def self.on_server_link(server_name : String)
      if services_server?
        # Send full services sync to new server
        NetworkSync.send_full_sync(server_name)

        # Announce that we are the services server
        NetworkSync.send_to_server(server_name, "SERVICES #{Server.config.host}")
      end
    end

    # Handle server split - check if services server disconnected
    def self.on_server_split(server_name : String)
      if @@services_server == server_name
        Log.warn { "Services server #{server_name} disconnected" }
        @@services_server = nil
        @@is_services_server = false

        # In a real implementation, you might want to elect a new services server
        # or have a fallback mechanism
      end
    end

    # Create virtual service users on all servers
    def self.propagate_service_users
      return unless services_server?

      # Introduce ChanServ to the network
      NetworkSync.broadcast_to_network(":#{Server.config.host} NICK ChanServ 1 #{Time.utc.to_unix} services #{Server.config.host} +o :Channel Registration Service")

      # Introduce UserServ to the network
      NetworkSync.broadcast_to_network(":#{Server.config.host} NICK UserServ 1 #{Time.utc.to_unix} services #{Server.config.host} +o :User Registration Service")
    end

    # Check if a nickname is a service (network-wide)
    def self.service_nick?(nickname : String) : Bool
      # Services are always considered services regardless of which server they're on
      case nickname.downcase
      when "chanserv", "userserv"
        true
      else
        false
      end
    end
  end
end
