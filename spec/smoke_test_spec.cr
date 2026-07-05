require "./spec_helper"

describe "Smoke Test" do
  it "can build and start server" do
    # Build server
    system("crystal build src/circed.cr -o circed_test").should be_true

    # Create test config
    File.write("test_smoke.yml", <<-YAML
      host: 0.0.0.0
      port: 19999
      network: TestNetwork
      max_users: 100
      server_name: smoke_test
      link_password: test_password
      YAML
    )

    # Start server
    puts "Starting server..."
    process = Process.new(
      command: "./circed_test",
      args: ["test_smoke.yml"],
      input: Process::Redirect::Close,
      output: Process::Redirect::Close,
      error: Process::Redirect::Close
    )
    puts "Server PID: #{process.pid}"

    deadline = Time.monotonic + 2.seconds
    until Time.monotonic > deadline
      begin
        socket = TCPSocket.new("localhost", 19999)
        socket.close
        break
      rescue IO::Error
        sleep 0.05.seconds
      end
    end

    # Check if running
    running = Process.exists?(process.pid)
    puts "Process exists check: #{running}"

    running.should be_true

    # Clean up
    process.signal(Signal::TERM)
    process.wait rescue nil

    File.delete("test_smoke.yml")
  end
end
