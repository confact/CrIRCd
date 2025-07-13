require "../../spec_helper"

describe Circed::Actions::Nick do
  before_each do
    clear_repositories
  end

  after_each do
    clear_repositories
  end

  it "changes a user's nickname" do
    sender = create_test_client("Alice")
    new_nickname = "Alice1"

    Circed::Actions::Nick.call(sender, new_nickname)

    sender.nickname.should eq(new_nickname)
    user_repository.has_client?(new_nickname).should be_true
    user_repository.has_client?("Alice").should be_false
  end

  it "does not allow to change to an already used nickname" do
    sender = create_test_client("Alice")
    other_user = create_test_client("Bob")
    new_nickname = "Bob"

    Circed::Actions::Nick.call(sender, new_nickname)

    sender.nickname.should eq("Alice")
    # sender.received_errors.should include({error: Numerics::ERR_NICKNAMEINUSE, message: "Nickname is already in used"})
  end

  it "sets a nickname for the first time" do
    sender = create_test_client("test")
    new_nickname = "Alice"

    Circed::Actions::Nick.call(sender, new_nickname)

    sender.nickname.should eq(new_nickname)
    user_repository.has_client?(new_nickname).should be_true
  end
end
