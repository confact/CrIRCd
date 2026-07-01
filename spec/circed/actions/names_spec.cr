require "../../spec_helper"

describe Circed::Actions::Names do
  before_each do
    clear_repositories
  end

  after_each do
    clear_repositories
  end

  it "renders channel privilege prefixes from member modes" do
    sender = create_test_client("Alice")
    create_test_client("Bob")
    create_test_client("Carol")
    channel_name = "#test"

    channel = create_test_channel(channel_name)
    channel.add_member("Alice")
    channel.members["Alice"] << 'o'
    channel.add_member("Bob")
    channel.members["Bob"] << 'v'
    channel.add_member("Carol")

    Circed::Actions::Names.call(sender, channel_name)

    socket = sender.socket.as(DummySocket)
    socket.sent_data.join.should contain(" 353 Alice = #test :@Alice +Bob Carol")
    socket.sent_data.join.should contain(" 366 Alice #test :End of /NAMES list")
  end
end
