# Dependency injection container for managing service instances
module Circed
  module Infrastructure
    class Container
      # Use a union type to store service instances
      alias ServiceInstance = Repositories::UserRepository | Repositories::ChannelRepository | Repositories::ServerRepository | Services::AuthenticationService | Services::NotificationService | Services::IRCService
      
      @@instances = Hash(String, ServiceInstance).new

      def self.register(type : T.class, instance : T) forall T
        @@instances[type.name] = instance.as(ServiceInstance)
      end

      def self.resolve(type : T.class) : T forall T
        instance = @@instances[type.name]?
        raise "Service #{type.name} not registered" unless instance
        instance.as(T)
      end

      def self.registered?(type : T.class) : Bool forall T
        @@instances.has_key?(type.name)
      end

      def self.clear
        @@instances.clear
      end

      # Factory method to create and register all default services
      def self.setup_default_services(config : Config)
        # Create repositories
        user_repo = Repositories::UserRepository.new
        channel_repo = Repositories::ChannelRepository.new
        server_repo = Repositories::ServerRepository.new

        # Create services
        auth_service = Services::AuthenticationService.new(config)
        notification_service = Services::NotificationService.new(user_repo, channel_repo)
        irc_service = Services::IRCService.new(user_repo, channel_repo, notification_service)

        # Register in container
        register(Repositories::UserRepository, user_repo)
        register(Repositories::ChannelRepository, channel_repo)
        register(Repositories::ServerRepository, server_repo)
        register(Services::AuthenticationService, auth_service)
        register(Services::NotificationService, notification_service)
        register(Services::IRCService, irc_service)
      end
    end

    # Service locator for backward compatibility during migration
    module ServiceLocator
      def self.user_repository : Repositories::UserRepository
        Container.resolve(Repositories::UserRepository)
      end

      def self.channel_repository : Repositories::ChannelRepository
        Container.resolve(Repositories::ChannelRepository)
      end

      def self.server_repository : Repositories::ServerRepository
        Container.resolve(Repositories::ServerRepository)
      end

      def self.notification_service : Services::NotificationService
        Container.resolve(Services::NotificationService)
      end

      def self.authentication_service : Services::AuthenticationService
        Container.resolve(Services::AuthenticationService)
      end

      def self.irc_service : Services::IRCService
        Container.resolve(Services::IRCService)
      end
    end
  end
end