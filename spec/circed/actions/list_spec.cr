require "../../spec_helper"

describe Circed::Actions::List do
  before_each { clear_repositories }
  after_each { clear_repositories }

  it "formats replies with one server prefix" do
    sender = create_test_client("Alice")

    Circed::Actions::List.call(sender)

    output = sender.socket.as(DummySocket).sent_data.join
    output.should contain(":#{Circed::Server.name} #{Circed::Numerics::RPL_LISTSTART}")
    output.should_not contain("::#{Circed::Server.name}")
  end

  it "lists only requested visible channels" do
    sender = create_test_client("Alice")
    create_test_channel("#one")
    create_test_channel("#two")

    Circed::Actions::List.call(sender, "#one")

    output = sender.socket.as(DummySocket).sent_data.join
    output.should contain(" 322 Alice #one ")
    output.should_not contain(" 322 Alice #two ")
  end

  it "hides private channels from non-members" do
    sender = create_test_client("Alice")
    channel = create_test_channel("#private")
    channel.modes << 'p'

    Circed::Actions::List.call(sender)

    sender.socket.as(DummySocket).sent_data.join.should_not contain(" 322 Alice #private ")
  end
end
