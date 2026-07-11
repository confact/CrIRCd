require "../spec_helper"

describe Circed::Format do
  it "serializes IRC messages directly to an IO" do
    io = IO::Memory.new

    Circed::Format.message(io, ":irc.example", "NOTICE", "alice", ":hello world")

    io.to_s.should eq(":irc.example NOTICE alice :hello world\r\n")
  end
end
