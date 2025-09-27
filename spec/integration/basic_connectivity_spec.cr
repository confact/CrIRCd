require "../spec_helper"

describe "Basic Connectivity" do
  env = IntegrationHelper::TestEnvironment.new

  after_each do
    env.teardown
  end

  it "can connect to server" do
    env.setup_single_server(ssl_enabled: false)

    # Just try to connect
    socket = TCPSocket.new("localhost", 16667)
    socket.should_not be_nil

    # Send NICK and USER
    socket.write("NICK TestUser\r\n".to_slice)
    socket.write("USER test 0 * :Test User\r\n".to_slice)
    socket.flush

    # Read responses - should get welcome messages
    sleep 1.second
    responses = [] of String?
    5.times do
      if line = socket.gets(chomp: false)
        responses << line
        puts "Response: #{line.inspect}"
      end
    end

    responses.should_not be_empty
    responses.any? { |response| response && response.includes?("001") }.should be_true

    socket.close
  end
end
