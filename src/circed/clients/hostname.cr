require "../network/ssl_socket"

module Circed
  class Hostname
    def self.get_hostname(ip_address : String) : String
      return "localhost" if {"localhost", "::1", "127.0.0.1"}.includes?(ip_address)

      ip_address
    end

    def self.get_hostname(socket : Network::SSLSocket::IRCSocket) : String
      return "localhost" if socket.nil?
      return "localhost" if socket.class.name == "DummySocket"

      case socket
      when TCPSocket
        get_hostname(socket.remote_address.address)
      when OpenSSL::SSL::Socket::Server, OpenSSL::SSL::Socket::Client
        # For SSL sockets, we can't easily get the remote address
        # Return a default value
        "ssl.client"
      else
        "unknown"
      end
    end
  end
end
