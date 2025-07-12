require "spec"
require "fast_irc"
require "./support/**"
ENV["CIRCED_TEST"] = "true"
require "../src/circed"

def create_test_client(nickname : String) : Circed::Client
  socket = DummySocket.new
  buffer = ["NICK #{nickname}", "USER test test localhost :#{nickname}"]
  client = Circed::Client.new(socket, buffer)
  # The client will process the buffer during initialization
  client
end
