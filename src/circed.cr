require "fast_irc"
require "./circed/mixins/**"
require "./circed/actions/mixins/**"
require "./circed/**"

# TODO: Write documentation for `Circed`
module Circed
  VERSION = "0.1.1"
end

Log.setup_from_env

Circed::Server.start unless ENV["CIRCED_TEST"]?
