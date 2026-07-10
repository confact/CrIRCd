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
    create_test_client("Bob") # Create user with nickname "Bob" to make it unavailable
    new_nickname = "Bob"

    Circed::Actions::Nick.call(sender, new_nickname)

    sender.nickname.should eq("Alice")
    # sender.received_errors.should include({error: Numerics::ERR_NICKNAMEINUSE, message: "Nickname is already in used"})
  end

  it "allows changing only the case of a nickname" do
    sender = create_test_client("Alice[One]")

    Circed::Actions::Nick.call(sender, "aLICE{oNE}")

    sender.nickname.should eq("aLICE{oNE}")
    user_repository.get_client("Alice[One]").should eq(sender)
  end

  it "rejects an RFC1459-equivalent nickname owned by another user" do
    sender = create_test_client("Alice")
    create_test_client("Bob[One]")

    Circed::Actions::Nick.call(sender, "bOB{oNE}")

    sender.nickname.should eq("Alice")
  end

  it "sets a nickname for the first time" do
    sender = create_test_client("test")
    new_nickname = "Alice"

    Circed::Actions::Nick.call(sender, new_nickname)

    sender.nickname.should eq(new_nickname)
    user_repository.has_client?(new_nickname).should be_true
  end

  it "does not immediately reuse a nickname released by a split" do
    sender = create_test_client("Alice")
    Circed::Network::NetworkState.add_user("Bob", "bob", "host", "Bob", "remote")
    Circed::Network::NetworkState.remove_user("Bob")

    Circed::Actions::Nick.call(sender, "Bob")

    sender.nickname.should eq("Alice")
  end
end
