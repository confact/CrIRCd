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
    create_test_client("Dave")
    channel_name = "#test"

    channel = create_test_channel(channel_name)
    channel.add_member("Alice")
    channel.members["Alice"] << 'o'
    channel.add_member("Bob")
    channel.members["Bob"] << 'v'
    channel.add_member("Carol")
    channel.add_member("Dave")
    channel.members["Dave"] << 'h'

    Circed::Actions::Names.call(sender, channel_name)

    socket = sender.socket.as(DummySocket)
    socket.sent_data.join.should contain(" 353 Alice = #test :@Alice +Bob Carol %Dave")
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
    data.should contain(" 353 Alice = #one Alice")
    data.should contain(" 366 Alice #one :End of /NAMES list")
    data.should contain(" 353 Alice = #two Alice")
    data.should contain(" 366 Alice #two :End of /NAMES list")
  end

  it "lists all visible channels once when no channel is given" do
    sender = create_test_client("Alice")
    public_channel = create_test_channel("#public")
    public_channel.add_member("Bob")
    private_channel = create_test_channel("#private")
    private_channel.add_member("Bob")
    private_channel.modes << 'p'

    Circed::Actions::Names.call(sender)

    data = sender.socket.as(DummySocket).sent_data.join
    data.should contain(" 353 Alice = #public Bob")
    data.should_not contain("#private")
    data.scan(/ 366 Alice \* /).size.should eq(1)
  end

  it "uses the private channel symbol for members" do
    sender = create_test_client("Alice")
    channel = create_test_channel("#private")
    channel.add_member("Alice")
    channel.modes << 'p'

    Circed::Actions::Names.call(sender, "#private")

    sender.socket.as(DummySocket).sent_data.join.should contain(" 353 Alice * #private Alice")
  end

  it "returns only end-of-names for hidden channels" do
    sender = create_test_client("Alice")
    channel = create_test_channel("#secret")
    channel.modes << 's'

    Circed::Actions::Names.call(sender, "#secret")

    data = sender.socket.as(DummySocket).sent_data.join
    data.should_not contain(" 353 Alice ")
    data.should contain(" 366 Alice #secret :End of /NAMES list")
  end

  it "reuses the output buffer between name chunks" do
    sender = create_test_client("Alice")
    channel = create_test_channel("#many")
    10.times { |index| channel.add_member("User#{index}") }

    Circed::Infrastructure::ServiceLocator.irc_service.join_channel(sender, channel.name)

    replies = sender.socket.as(DummySocket).sent_data.select(&.includes?(" 353 "))
    replies.size.should eq(2)
    replies.last.should contain("Alice")
    replies.last.should_not contain("User0")
  end
end
