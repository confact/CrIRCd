# Service for handling authentication of servers and users
module Circed
  module Services
    class AuthenticationService
      include Core::Authenticator

      def initialize(@config : Config)
      end

      def authenticate(credentials : Core::AuthenticationCredentials) : Core::AuthenticationResult
        case credentials
        when ServerCredentials
          authenticate_server(credentials)
        when UserCredentials
          authenticate_user(credentials)
        else
          Core::AuthenticationResult::Failed
        end
      end

      private def authenticate_server(credentials : ServerCredentials) : Core::AuthenticationResult
        # Check if server is in allowed list
        unless server_allowed?(credentials.server_name)
          return Core::AuthenticationResult::ServerNotAllowed
        end

        # Validate password
        unless valid_server_password?(credentials.password)
          return Core::AuthenticationResult::InvalidPassword
        end

        # Validate token if provided
        if credentials.token && !valid_server_token?(credentials.token)
          return Core::AuthenticationResult::InvalidToken
        end

        Core::AuthenticationResult::Success
      end

      private def authenticate_user(credentials : UserCredentials) : Core::AuthenticationResult
        # Basic user authentication - can be extended for password auth, etc.
        if valid_nickname?(credentials.nickname) && valid_username?(credentials.username)
          Core::AuthenticationResult::Success
        else
          Core::AuthenticationResult::Failed
        end
      end

      private def server_allowed?(server_name : String?) : Bool
        return false unless server_name

        # Check against configured allowed servers
        @config.linked_servers.any? { |linked_server| linked_server.host == server_name }
      end

      private def valid_server_password?(password : String?) : Bool
        return false unless password
        password == @config.link_password
      end

      private def valid_server_token?(token : String?) : Bool
        # Simple token validation - in production this should be more sophisticated
        return false unless token
        token.size > 0 && token != "0"
      end

      private def valid_nickname?(nickname : String?) : Bool
        return false unless nickname
        return false if nickname.empty?
        return false if nickname.size > 30

        # IRC nickname rules: start with letter, contain letters/numbers/special chars
        nickname.matches?(/^[a-zA-Z][a-zA-Z0-9\-\[\]\\`^{}_]*$/)
      end

      private def valid_username?(username : String?) : Bool
        return false unless username
        return false if username.empty?
        return false if username.size > 32

        # Username rules: no spaces or special IRC characters
        !username.includes?(' ') && !username.includes?('@') && !username.includes?('!')
      end
    end

    # Specific credential types
    class ServerCredentials < Core::AuthenticationCredentials
      def server_name : String
        name = @server_name
        return "" unless name
        name
      end

      def password : String
        pwd = @password
        return "" unless pwd
        pwd
      end

      def initialize(server_name : String, password : String, token : String? = nil)
        super(password, server_name, token)
      end
    end

    class UserCredentials < Core::AuthenticationCredentials
      property nickname : String
      property username : String
      property realname : String
      property hostname : String

      def initialize(@nickname : String, @username : String, @realname : String, @hostname : String)
        super(nil, nil, nil)
      end
    end

    # Authentication state management
    class AuthenticationSession
      property state : AuthenticationState
      property credentials : Core::AuthenticationCredentials?
      property started_at : Time
      property attempts : Int32

      def initialize
        @state = AuthenticationState::Pending
        @started_at = Time.utc
        @attempts = 0
      end

      def record_attempt
        @attempts += 1
      end

      def too_many_attempts? : Bool
        @attempts >= 3
      end

      def expired? : Bool
        Time.utc - @started_at > 30.seconds
      end

      def complete? : Bool
        @state == AuthenticationState::Completed
      end

      def failed? : Bool
        @state == AuthenticationState::Failed
      end
    end

    enum AuthenticationState
      Pending
      InProgress
      Completed
      Failed
      Expired
    end

    # Authentication manager for handling ongoing sessions
    class AuthenticationManager
      def initialize(@service : AuthenticationService)
        @sessions = Hash(String, AuthenticationSession).new
      end

      def start_session(identifier : String) : AuthenticationSession
        session = AuthenticationSession.new
        @sessions[identifier] = session
        session
      end

      def get_session(identifier : String) : AuthenticationSession?
        @sessions[identifier]?
      end

      def complete_authentication(identifier : String, credentials : Core::AuthenticationCredentials) : Core::AuthenticationResult
        session = get_session(identifier)
        return Core::AuthenticationResult::Failed unless session

        return Core::AuthenticationResult::Failed if session.expired?
        return Core::AuthenticationResult::Failed if session.too_many_attempts?

        session.record_attempt
        result = @service.authenticate(credentials)

        if result == Core::AuthenticationResult::Success
          session.state = AuthenticationState::Completed
          session.credentials = credentials
        else
          session.state = AuthenticationState::Failed if session.too_many_attempts?
        end

        result
      end

      def cleanup_expired_sessions
        expired_sessions = @sessions.select { |_, session| session.expired? || session.failed? }
        expired_sessions.each { |identifier, _| @sessions.delete(identifier) }
      end
    end
  end
end
