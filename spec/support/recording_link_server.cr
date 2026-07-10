class RecordingLinkServer < Circed::LinkServer
  getter sent_messages = [] of String

  def initialize(@name : String, target_host : String? = nil, @target_port : Int32 = 6667)
    @target_host = target_host || @name
  end

  def safe_send(message : String) : Bool
    @sent_messages << message
    true
  end

  def close(reason : String = "Closing connection")
    @sent_messages << "CLOSE #{reason}"
  end

  def close_from_peer(reason : String)
    Circed::ServerHandler.remove_server(self)
    @sent_messages << "CLOSE #{reason}"
  end

  def closed? : Bool
    false
  end
end
