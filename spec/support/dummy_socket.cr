require "socket"

class DummySocket < IPSocket
  def initialize
    super(Socket::Family::INET, Socket::Type::STREAM, Socket::Protocol::TCP, 0)
  end
  def read(slice : Bytes)
    0
  end

  def write(slice : Bytes) : Nil
    slice.size
  end

  def close
  end
end