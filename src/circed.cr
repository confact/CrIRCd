require "fast_irc"
require "./circed/**"

module Circed
  VERSION = "0.1.1"
end

Log.setup_from_env

# Start server if this is the main file being run
if File.basename(PROGRAM_NAME) == "circed" || File.basename(PROGRAM_NAME) == "circed_test"
  Circed::Server.start
end
