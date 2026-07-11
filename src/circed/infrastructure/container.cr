module Circed
  module Infrastructure
    module Container
      @@user_repository : Repositories::UserRepository? = nil
      @@channel_repository : Repositories::ChannelRepository? = nil
      @@dns_resolver_service : Services::DNSResolverService? = nil
      @@notification_service : Services::NotificationService? = nil
      @@irc_service : Services::IRCService? = nil

      def self.setup_default_services(config : Config) : Nil
        user_repository = Repositories::UserRepository.new
        channel_repository = Repositories::ChannelRepository.new
        notification_service = Services::NotificationService.new(user_repository, channel_repository)

        @@user_repository = user_repository
        @@channel_repository = channel_repository
        @@dns_resolver_service = Services::DNSResolverService.new(config.dns)
        @@notification_service = notification_service
        @@irc_service = Services::IRCService.new(user_repository, channel_repository, notification_service)
      end

      def self.user_repository : Repositories::UserRepository
        @@user_repository || raise "Services not initialized"
      end

      def self.channel_repository : Repositories::ChannelRepository
        @@channel_repository || raise "Services not initialized"
      end

      def self.dns_resolver_service : Services::DNSResolverService
        @@dns_resolver_service || raise "Services not initialized"
      end

      def self.dns_resolver_service? : Services::DNSResolverService?
        @@dns_resolver_service
      end

      def self.notification_service : Services::NotificationService
        @@notification_service || raise "Services not initialized"
      end

      def self.irc_service : Services::IRCService
        @@irc_service || raise "Services not initialized"
      end
    end

    ServiceLocator = Container
  end
end
