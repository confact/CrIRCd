require "../../spec_helper"

describe Circed::Actions::Whois do
  before_each do
    clear_repositories
  end

  after_each do
    clear_repositories
  end

  it "reports global operator status" do
    sender = create_test_client("Alice")
    create_test_client("Bob")
    user_repository["Bob"]?.try { |user| user.modes << 'o' }

    Circed::Actions::Whois.call(sender, "Bob")

    sender.socket.as(DummySocket).sent_data.join.should contain(" 313 Alice Bob :is an IRC operator")
  end

  it "reports local operator status" do
    sender = create_test_client("Alice")
    create_test_client("Bob")
    user_repository["Bob"]?.try { |user| user.modes << 'O' }

    Circed::Actions::Whois.call(sender, "Bob")

    sender.socket.as(DummySocket).sent_data.join.should contain(" 313 Alice Bob :is an IRC operator")
  end

  it "does not report operator status for normal users" do
    sender = create_test_client("Alice")
    create_test_client("Bob")

    Circed::Actions::Whois.call(sender, "Bob")

    sender.socket.as(DummySocket).sent_data.join.should_not contain(" 313 Alice Bob")
  end

  it "hides private channels from non-members" do
    sender = create_test_client("Alice")
    create_test_client("Bob")
    channel = create_test_channel("#private")
    channel.add_member("Bob")
    channel.modes << 'p'

    Circed::Actions::Whois.call(sender, "Bob")

    sender.socket.as(DummySocket).sent_data.join.should_not contain("#private")
  end

  it "includes channel privilege prefixes" do
    sender = create_test_client("Alice")
    create_test_client("Bob")
    channel = create_test_channel("#shared")
    channel_repository.add_member("#shared", "Alice")
    channel_repository.add_member("#shared", "Bob")
    channel.members["Bob"] << 'o'

    Circed::Actions::Whois.call(sender, "Bob")

    sender.socket.as(DummySocket).sent_data.join.should contain(" 319 Alice Bob @#shared")
  end
end
