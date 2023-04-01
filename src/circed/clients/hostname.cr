require "durian"

module Circed
  class Hostname
    def self.get_hostname(ip_address : String) : String
      return ip_address if ip_address == "localhost" || ip_address == "::1" || ip_address == "127.0.0.1"

      buffer = uninitialized UInt8[4096_i32]

      reverse_dns = ip_to_reverse_dns(ip_address)

      request = Durian::Packet.new Durian::Protocol::UDP, Durian::Packet::QRFlag::Query
      request.add_query reverse_dns, Durian::RecordFlag::PTR

      udp_socket = UDPSocket.new
      udp_socket.connect Socket::IPAddress.new "8.8.8.8", 53_i32
      udp_socket.send request.to_slice

      length, _ = udp_socket.receive buffer.to_slice
      response = Durian::Packet.from_io(Durian::Protocol::UDP, IO::Memory.new(buffer.to_slice[0_i32, length]))
      resource_record = response.try(&.answers).try(&.first?).try(&.resourceRecord)
      if resource_record.is_a?(Durian::Record::PTR)
        hostname = resource_record.domainName
      else
        hostname = ip_address
      end
      hostname
    end

    def self.get_hostname(socket : TCPSocket) : String
      if socket.nil? || socket.is_a?(DummySocket)
        return "localhost"
      end
      get_hostname(socket.remote_address.address)
    end

    def self.get_hostname(socket : IPSocket) : String
      if socket.nil? || socket.is_a?(DummySocket)
        return "localhost"
      end
      get_hostname(socket.remote_address.address)
    end

    def self.ip_to_reverse_dns(ip_address : String) : String
      ip_parts = ip_address.split(".")
      ip_parts.reverse.join(".") + ".in-addr.arpa"
    end
  end
end
