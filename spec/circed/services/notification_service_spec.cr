require "../../spec_helper"

describe Circed::Services::NotificationService do
  before_each { clear_repositories }
  after_each { clear_repositories }

  it "delivers to a channel without echoing to the excluded user" do
    alice = create_test_client("Alice")
    bob = create_test_client("Bob")
    channel_repository.add_member("#test", "Alice")
    channel_repository.add_member("#test", "Bob")

    Circed::Infrastructure::ServiceLocator.notification_service.notify_channel("#test", ":Alice PRIVMSG #test :hello", "Alice")

    alice.socket.as(DummySocket).sent_data.none?(&.includes?("PRIVMSG #test :hello")).should be_true
    bob.socket.as(DummySocket).sent_data.join.should contain("PRIVMSG #test :hello")
  end

  it "delivers directly to one user" do
    bob = create_test_client("Bob")

    Circed::Infrastructure::ServiceLocator.notification_service.notify_user("Bob", ":Alice NOTICE Bob :hello")

    bob.socket.as(DummySocket).sent_data.join.should contain("NOTICE Bob :hello")
  end

  it "notifies a shared-channel peer only once" do
    alice = create_test_client("Alice")
    bob = create_test_client("Bob")
    channel_repository.add_member("#one", "Alice")
    channel_repository.add_member("#one", "Bob")
    channel_repository.add_member("#two", "Alice")
    channel_repository.add_member("#two", "Bob")

    Circed::Infrastructure::ServiceLocator.notification_service.notify_shared_channels("Alice", ":Alice NICK Alicia")

    alice.socket.as(DummySocket).sent_data.none?(&.includes?("NICK Alicia")).should be_true
    bob.socket.as(DummySocket).sent_data.count(&.includes?("NICK Alicia")).should eq(1)
  end
end
