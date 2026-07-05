require "./base_action"
require "../network/ssl_socket"

module Circed
  module Actions
    class Starttls < BaseAction
      def self.call(client : Client)
        return unless starttls_available?
        return send_error(client, ":STARTTLS not available") unless ssl_enabled?
        return send_error(client, ":Already using TLS") if already_using_ssl?(client)
        return send_error(client, ":Cannot upgrade connection") unless valid_tcp_socket?(client)

        upgrade_connection(client)
      end

      private def self.ssl_enabled?
        ssl_config = Server.config.ssl
        ssl_config && ssl_config.enabled? && ssl_config.starttls?
      end

      private def self.starttls_available?
        ssl_enabled?
      end

      private def self.already_using_ssl?(client : Client) : Bool
        if socket = client.socket
          Network::SSLSocket.ssl?(socket)
        else
          false
        end
      end

      private def self.valid_tcp_socket?(client : Client) : Bool
        client.socket.is_a?(TCPSocket)
      end

      private def self.send_error(client : Client, message : String)
        client.send_message(Server.clean_name, Numerics::ERR_STARTTLS, client.nickname || "*", message)
      end

      private def self.upgrade_connection(client : Client)
        tcp_socket = client.socket.as(TCPSocket)
        ssl_config = Server.config.ssl
        return unless ssl_config

        client.send_message_now(Server.clean_name, Numerics::RPL_STARTTLS, client.nickname || "*", ":STARTTLS successful, proceed with TLS handshake")

        begin
          ssl_socket = perform_tls_handshake(tcp_socket, ssl_config)
          client.socket = ssl_socket
          log_success(client, ssl_socket)
        rescue ex : OpenSSL::SSL::Error
          close_after_failure(client, "STARTTLS failed", ex.message)
        rescue ex : IO::TimeoutError
          close_after_failure(client, "STARTTLS timed out")
        rescue ex
          close_after_failure(client, "STARTTLS failed", ex.message)
        end
      end

      private def self.perform_tls_handshake(tcp_socket : TCPSocket, ssl_config : Config::SSLConfig)
        tcp_socket.read_timeout = 10.seconds
        tcp_socket.write_timeout = 10.seconds

        ssl_context = Network::SSLSocket.create_context(ssl_config)
        Network::SSLSocket.upgrade_to_ssl(tcp_socket, ssl_context)
      end

      private def self.log_success(client : Client, ssl_socket)
        peer_info = Network::SSLSocket.get_peer_info(ssl_socket)
        suffix = peer_info ? " (#{peer_info})" : ""
        Log.info { "STARTTLS completed for #{client.nickname || client.host}#{suffix}" }
      end

      private def self.close_after_failure(client : Client, message : String, detail : String? = nil)
        suffix = detail ? ": #{detail}" : ""
        Log.error { "#{message} for #{client.nickname || client.host}#{suffix}" }
        client.close
      end
    end
  end
end
