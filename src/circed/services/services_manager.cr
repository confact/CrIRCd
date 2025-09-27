require "./database"
require "./chanserv"
require "./userserv"

module Circed::Services
  # Manager for IRC services
  class ServicesManager
    @@instance : ServicesManager?
    @@chanserv : ChanServ?
    @@userserv : UserServ?

    def self.instance : ServicesManager
      @@instance ||= new
    end

    def self.setup(db_path : String = "services.db")
      Database.setup(db_path)
      instance.initialize_services
    end

    def initialize_services
      @@chanserv = ChanServ.new
      @@userserv = UserServ.new

      # Register services with the network
      @@chanserv.try(&.register_with_network)
      @@userserv.try(&.register_with_network)

      Log.info { "IRC Services initialized: ChanServ, UserServ" }
    end

    def self.chanserv : ChanServ?
      @@chanserv
    end

    def self.userserv : UserServ?
      @@userserv
    end

    # Handle a message directed to a service
    def self.handle_service_message(sender : String, target : String, message : String)
      # Only handle if we are the services server
      return unless ServicesHub.services_server?

      # Parse the message
      parts = message.split(' ', 2)
      command = parts[0]
      params = parts[1]?.try(&.split(' ')) || [] of String

      case target.downcase
      when "chanserv"
        @@chanserv.try(&.handle_message(sender, command, params))
        # Broadcast relevant changes to network
        broadcast_if_needed(sender, target, command, params)
      when "userserv"
        @@userserv.try(&.handle_message(sender, command, params))
        # Broadcast relevant changes to network
        broadcast_if_needed(sender, target, command, params)
      else
        # Unknown service
        if user = get_user(sender)
          user.send_message(":#{target}!services@#{Server.config.host} NOTICE #{sender} :Unknown service.")
        end
      end
    end

    # Broadcast changes that affect network state
    private def self.broadcast_if_needed(sender : String, target : String, command : String, params : Array(String))
      case target.downcase
      when "chanserv"
        case command.upcase
        when "REGISTER"
          if params.size >= 2
            channel_name = params[0]
            if registered_channel = @@chanserv.try(&.get_registered_channel(channel_name))
              NetworkSync.broadcast_channel_registration(
                channel_name, registered_channel.founder, registered_channel.topic, registered_channel.modes
              )
            end
          end
        when "DROP"
          if params.size >= 1
            NetworkSync.broadcast_channel_drop(params[0])
          end
        end
      when "userserv"
        case command.upcase
        when "REGISTER"
          NetworkSync.broadcast_user_identification(sender, true)
        when "IDENTIFY"
          NetworkSync.broadcast_user_identification(sender, true)
        end
      end
    end

    # Check if a nickname is a service
    def self.service?(nickname : String) : Bool
      case nickname.downcase
      when "chanserv", "userserv"
        true
      else
        false
      end
    end

    # Check if user is identified with UserServ
    def self.user_identified?(nickname : String) : Bool
      @@userserv.try(&.identified?(nickname)) || false
    end

    # Get user access level for a channel
    def self.get_channel_access(channel_name : String, nickname : String) : AccessLevel
      return AccessLevel::None unless chanserv = @@chanserv

      if registered_channel = chanserv.get_registered_channel(channel_name)
        registered_channel.get_access_level(nickname)
      else
        AccessLevel::None
      end
    end

    # Check if channel is registered
    def self.channel_registered?(channel_name : String) : Bool
      return false unless chanserv = @@chanserv
      !chanserv.get_registered_channel(channel_name).nil?
    end

    private def self.get_user(nickname : String)
      Circed::Infrastructure::ServiceLocator.user_repository.get_client(nickname)
    end
  end
end
