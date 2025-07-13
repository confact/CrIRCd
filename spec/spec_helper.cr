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
  client = Circed::Client.new(socket, buffer)

  # Directly set the nickname for testing
  client.nickname = nickname

  # Add client to user repository directly instead of through UserHandler
  user_repository.add_client(client)

  client
end
