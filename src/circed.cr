require "fast_irc"
require "./circed/mixins/**"
require "./circed/actions/mixins/**"
require "./circed/network/**"
require "./circed/commands/**"
require "./circed/**"
require "../spec/support/dummy_socket.cr"

module Circed
  VERSION = "0.1.1"
end

Log.setup_from_env

Circed::Server.start unless ENV["CIRCED_TEST"]?
