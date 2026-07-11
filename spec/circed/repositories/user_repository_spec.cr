require "../../spec_helper"

describe Circed::Repositories::UserRepository do
  before_each { clear_repositories }
  after_each { clear_repositories }

  it "looks up users and clients using RFC1459 casemapping" do
    client = create_test_client("Alice[Ops]")

    user_repository["aLICE{Ops}"]?.try(&.nickname).should eq("Alice[Ops]")
    user_repository.get_client("ALICE{OPS}").should be(client)
  end

  it "supports case-only nickname changes" do
    client = create_test_client("Alice")

    user_repository.change_nickname("ALICE", "alice").should be_true

    user_repository["Alice"]?.try(&.nickname).should eq("alice")
    user_repository.get_client("ALICE").should be(client)
  end
end
