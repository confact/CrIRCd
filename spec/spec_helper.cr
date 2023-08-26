require "spec"
require "fast_irc"
require "./support/**"
ENV["CIRCED_TEST"] = "true"
require "../src/circed"

def create_test_client(nickname : String) : Circed::Client
  client = Circed::Client.new(DummySocket.new)
  client.nickname = nickname
  client.set_user(["test", "test", "test", nickname])
  Circed::UserHandler.add_client(client)
  client
end