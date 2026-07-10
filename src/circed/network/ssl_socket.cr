require "openssl"
require "socket"

module Circed
  module Network
    # Wrapper module for SSL/TLS socket support
    module SSLSocket
      # Create an SSL context with appropriate settings for IRC
      def self.create_context(config : Config::SSLConfig) : OpenSSL::SSL::Context::Server
        context = OpenSSL::SSL::Context::Server.new

        # Set certificate and key files
        if cert_file = config.cert_file
          context.certificate_chain = cert_file
        end
        if key_file = config.key_file
          context.private_key = key_file
        end

        # Set SSL/TLS options for security
        context.add_options(
          OpenSSL::SSL::Options::NO_SSL_V2 |
          OpenSSL::SSL::Options::NO_SSL_V3 |
          OpenSSL::SSL::Options::NO_TLS_V1 |
          OpenSSL::SSL::Options::NO_TLS_V1_1 |
          OpenSSL::SSL::Options::SINGLE_DH_USE |
          OpenSSL::SSL::Options::SINGLE_ECDH_USE
        )

        # Set cipher list for modern security
        context.ciphers = "ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS"

        # Enable client certificate verification if configured
        if config.verify_mode?
          context.verify_mode = OpenSSL::SSL::VerifyMode::PEER
          if ca_file = config.ca_file
            context.ca_certificates = ca_file
          end
        else
          context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
        end

        context
      end

      # Create client SSL context for outgoing server connections
      def self.create_client_context(config : Config::SSLConfig? = nil, *, verify_mode : Bool = false) : OpenSSL::SSL::Context::Client
        context = OpenSSL::SSL::Context::Client.new

        # Set certificate and key if provided (for mutual TLS)
        cert_file = config.try(&.cert_file)
        key_file = config.try(&.key_file)
        if cert_file && key_file
          context.certificate_chain = cert_file
          context.private_key = key_file
        end

        # Set SSL/TLS options
        context.add_options(
          OpenSSL::SSL::Options::NO_SSL_V2 |
          OpenSSL::SSL::Options::NO_SSL_V3 |
          OpenSSL::SSL::Options::NO_TLS_V1 |
          OpenSSL::SSL::Options::NO_TLS_V1_1
        )

        # Set cipher list
        context.ciphers = "ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS"

        # Verify mode for server certificate
        if verify_mode || config.try(&.verify_mode?)
          context.verify_mode = OpenSSL::SSL::VerifyMode::PEER
          if ca_file = config.try(&.ca_file)
            context.ca_certificates = ca_file
          end
        else
          context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
        end

        context
      end

      # Wrap a TCPSocket with SSL
      def self.wrap_server_socket(tcp_socket : TCPSocket, context : OpenSSL::SSL::Context::Server) : OpenSSL::SSL::Socket::Server
        OpenSSL::SSL::Socket::Server.new(tcp_socket, context, sync_close: true)
      end

      # Wrap a client socket with SSL
      def self.wrap_client_socket(tcp_socket : TCPSocket, context : OpenSSL::SSL::Context::Client, hostname : String? = nil) : OpenSSL::SSL::Socket::Client
        OpenSSL::SSL::Socket::Client.new(tcp_socket, context, sync_close: true, hostname: hostname)
      end

      # Check if a socket supports STARTTLS upgrade
      def self.can_start_tls?(socket : IRCSocket) : Bool
        !ssl?(socket)
      end

      # Upgrade a plain socket to SSL (STARTTLS)
      def self.upgrade_to_ssl(socket : TCPSocket, context : OpenSSL::SSL::Context::Server) : OpenSSL::SSL::Socket::Server
        wrap_server_socket(socket, context)
      end

      # Check if socket is already SSL
      def self.ssl?(socket : IRCSocket) : Bool
        socket.is_a?(OpenSSL::SSL::Socket::Server) || socket.is_a?(OpenSSL::SSL::Socket::Client)
      end

      # Get peer certificate info for logging/validation
      def self.get_peer_info(socket : IRCSocket) : String?
        case socket
        when OpenSSL::SSL::Socket::Server, OpenSSL::SSL::Socket::Client
          if cert = socket.peer_certificate
            return "CN=#{cert.subject}"
          end
        end
        nil
      end

      # Abstract socket type that works with both SSL and plain sockets
      alias IRCSocket = TCPSocket | OpenSSL::SSL::Socket::Server | OpenSSL::SSL::Socket::Client
    end
  end
end
