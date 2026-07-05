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
    user_repository.get("Bob").try { |user| user.modes << 'o' }

    Circed::Actions::Whois.call(sender, "Bob")

    sender.socket.as(DummySocket).sent_data.join.should contain(" 313 Alice Bob :is an IRC operator")
  end

  it "reports local operator status" do
    sender = create_test_client("Alice")
    create_test_client("Bob")
    user_repository.get("Bob").try { |user| user.modes << 'O' }

    Circed::Actions::Whois.call(sender, "Bob")

    sender.socket.as(DummySocket).sent_data.join.should contain(" 313 Alice Bob :is an IRC operator")
  end

  it "does not report operator status for normal users" do
    sender = create_test_client("Alice")
    create_test_client("Bob")

    Circed::Actions::Whois.call(sender, "Bob")

    sender.socket.as(DummySocket).sent_data.join.should_not contain(" 313 Alice Bob")
  end
end
