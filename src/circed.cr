require "fast_irc"

# Core abstractions and interfaces
require "./circed/core/**"

# Domain entities
require "./circed/domain/**"

# Repositories
require "./circed/repositories/**"

# Services
require "./circed/services/**"

# Legacy modules (to be gradually refactored to use repository pattern)
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
