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

        client.send_message(Server.clean_name, Numerics::RPL_STARTTLS, client.nickname || "*", ":STARTTLS successful, proceed with TLS handshake")

        begin
          # Set timeout for STARTTLS handshake
          tcp_socket.read_timeout = 10.seconds
          tcp_socket.write_timeout = 10.seconds

          ssl_context = Network::SSLSocket.create_context(ssl_config)
          ssl_socket = Network::SSLSocket.upgrade_to_ssl(tcp_socket, ssl_context)
          client.socket = ssl_socket

          if peer_info = Network::SSLSocket.get_peer_info(ssl_socket)
            Log.info { "STARTTLS completed for #{client.nickname || client.host} (#{peer_info})" }
          else
            Log.info { "STARTTLS completed for #{client.nickname || client.host}" }
          end
        rescue ex : OpenSSL::SSL::Error
          Log.error { "STARTTLS failed for #{client.nickname || client.host}: #{ex.message}" }
          client.close
        rescue ex : IO::TimeoutError
          Log.error { "STARTLS timed out for #{client.nickname || client.host}" }
          client.close
        rescue ex
          Log.error { "STARTTLS failed for #{client.nickname || client.host}: #{ex.message}" }
          client.close
        end
      end
    end
  end
end
