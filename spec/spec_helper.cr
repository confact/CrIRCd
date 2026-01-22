require "spec"
require "fast_irc"
require "./support/**"
ENV["CIRCED_TEST"] = "true"
require "../src/circed"

# Initialize container for tests
Circed::Infrastructure::Container.setup_default_services(Circed::Server.config)

include RepositoryHelper

def create_test_client(nickname : String) : Circed::Client
  socket = DummySocket.new
  buffer = ["NICK #{nickname}", "USER test test localhost :#{nickname}"]
  client = Circed::Client.new(socket.as(Circed::Network::SSLSocket::IRCSocket), buffer)

  # Directly set the nickname for testing
  client.nickname = nickname

  # Create a domain user as well
  domain_user = Circed::Domain::User.new(nickname, "test", "localhost", nickname, "test_server")
  user_repository.add(nickname, domain_user)

  # Add client to user repository directly instead of through UserHandler
  user_repository.add_client(client)

  client
end

def create_test_link_server(buffer = ["PASS testpass", "SERVER remote.server.com 1 :Remote Server"])
  dummy_socket = DummySocket.new
  buffer.each { |line| dummy_socket.add_receive_data("#{line}\r\n") }
  remote_addr = Socket::IPAddress.new("127.0.0.1", 12345)
  Circed::LinkServer.new(dummy_socket.as(Circed::Network::SSLSocket::IRCSocket), buffer, remote_addr)
end
