require "durian"
require "../network/ssl_socket"

module Circed
  class Hostname
    GOOGLE_DNS_SERVER = "8.8.8.8"
    GOOGLE_DNS_PORT   = 53_i32

    def self.get_hostname(ip_address : String) : String
      return "localhost" if {"localhost", "::1", "127.0.0.1"}.includes?(ip_address)

      buffer = uninitialized UInt8[4096_i32]
      reverse_dns = ip_to_reverse_dns(ip_address)

      request = Durian::Packet.new Durian::Protocol::UDP, Durian::Packet::QRFlag::Query
      request.add_query reverse_dns, Durian::RecordFlag::PTR

      udp_socket = UDPSocket.new
      begin
        udp_socket.connect Socket::IPAddress.new GOOGLE_DNS_SERVER, GOOGLE_DNS_PORT
        udp_socket.send request.to_slice

        length, _ = udp_socket.receive buffer.to_slice
        response = Durian::Packet.from_io(Durian::Protocol::UDP, IO::Memory.new(buffer.to_slice[0_i32, length]))
        resource_record = response.try(&.answers).try(&.first?).try(&.resourceRecord)

        if resource_record.is_a?(Durian::Record::PTR)
          return resource_record.domainName
        end
      rescue e
        Log.warn(exception: e) { "Error fetching hostname" }
      ensure
        udp_socket.close
      end

      ip_address
    end

    def self.get_hostname(socket : Network::SSLSocket::IRCSocket) : String
      return "localhost" if socket.nil?

      case socket
      when TCPSocket
        # Handle test DummySocket
        if socket.class.name == "DummySocket"
          return "localhost"
        end
        get_hostname(socket.remote_address.address)
      when OpenSSL::SSL::Socket::Server, OpenSSL::SSL::Socket::Client
        # For SSL sockets, we can't easily get the remote address
        # Return a default value
        "ssl.client"
      else
        "unknown"
      end
    end

    def self.ip_to_reverse_dns(ip_address : String) : String
      ip_address.split(".").reverse!.join(".") + ".in-addr.arpa"
    end
  end
end
