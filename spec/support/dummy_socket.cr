require "socket"
require "../../src/circed/network/ssl_socket"

class DummySocket < IPSocket
  @receive_data : Array(String) = [] of String
  @current_index : Int32 = 0
  @closed : Bool = false

  def initialize
    super(Socket::Family::INET, Socket::Type::STREAM, Socket::Protocol::TCP, blocking: false)
  end

  def add_receive_data(data : String)
    @receive_data << data
  end

  def gets(delimiter = '\n', limit : Int32 = 0) : String?
    return nil if @closed || @current_index >= @receive_data.size

    line = @receive_data[@current_index]
    @current_index += 1
    line.chomp
  end

  def read(slice : Bytes)
    0
  end

  def write(slice : Bytes) : Nil
    slice.size
  end

  def puts(data : String)
    # Mock implementation - could store sent data if needed for testing
    return if @closed
    data.size # Return something truthy like real socket puts
  end

  def close
    @closed = true
  end

  def closed?
    @closed
  end

  def remote_address
    Socket::IPAddress.new("127.0.0.1", 12345)
  end
end
