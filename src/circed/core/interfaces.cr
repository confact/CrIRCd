# Core abstractions and interfaces for the IRC server
module Circed
  module Core
    # Base repository interface for managing entities
    module Repository(T)
      abstract def add(id : String, entity : T) : Void
      abstract def get(id : String) : T?
      abstract def remove(id : String) : Bool
      abstract def all : Array(T)
      abstract def size : Int32
      abstract def clear : Void
    end

    # Message handler interface for processing IRC messages
    module MessageHandler
      abstract def handle(message : FastIRC::Message, context : MessageContext) : Void
      abstract def can_handle?(command : String) : Bool
    end

    # Authentication interface
    module Authenticator
      abstract def authenticate(credentials : AuthenticationCredentials) : AuthenticationResult
    end

    # Message routing interface
    module MessageRouter
      abstract def route(message : FastIRC::Message, from : MessageSource) : Array(MessageDestination)
    end

    # Event notification interface
    module NotificationService
      abstract def notify(event : NotificationEvent, targets : Array(NotificationTarget)) : Void
    end

    # Message context for handlers
    class MessageContext
      getter sender : MessageSource
      getter timestamp : Time
      getter server_context : ServerContext?

      def initialize(@sender : MessageSource, @timestamp = Time.utc, @server_context = nil)
      end
    end

    # Base message source
    abstract class MessageSource
      abstract def identifier : String
      abstract def type : SourceType
    end

    enum SourceType
      LocalClient
      RemoteClient
      LocalServer
      RemoteServer
    end

    # Message destination
    abstract class MessageDestination
      abstract def deliver(message : String) : Bool
    end

    # Authentication types
    class AuthenticationCredentials
      property password : String?
      property server_name : String?
      property token : String?

      def initialize(@password = nil, @server_name = nil, @token = nil)
      end
    end

    enum AuthenticationResult
      Success
      InvalidPassword
      InvalidToken
      ServerNotAllowed
      Failed
    end

    # Event system
    abstract class NotificationEvent
      abstract def event_type : String
      abstract def data : Hash(String, String)
    end

    abstract class NotificationTarget
      abstract def receive_notification(event : NotificationEvent) : Void
    end

    # Server context for operations
    class ServerContext
      property config : Config
      property start_time : Time

      def initialize(@config : Config, @start_time = Time.utc)
      end
    end
  end
end
