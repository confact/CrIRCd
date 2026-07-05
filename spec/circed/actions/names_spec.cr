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

  it "handles comma-separated channel lists" do
    sender = create_test_client("Alice")

    first_channel = create_test_channel("#one")
    first_channel.add_member("Alice")

    second_channel = create_test_channel("#two")
    second_channel.add_member("Alice")

    Circed::Actions::Names.call(sender, "#one,#two")

    socket = sender.socket.as(DummySocket)
    data = socket.sent_data.join
    data.should contain(" 353 Alice = #one :Alice")
    data.should contain(" 366 Alice #one :End of /NAMES list")
    data.should contain(" 353 Alice = #two :Alice")
    data.should contain(" 366 Alice #two :End of /NAMES list")
  end
end
