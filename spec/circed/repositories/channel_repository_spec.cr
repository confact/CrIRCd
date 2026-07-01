require "../../spec_helper"

describe Circed::Repositories::ChannelRepository do
  before_each do
    clear_repositories
  end

  after_each do
    clear_repositories
  end

  it "indexes channels by nickname when members are added" do
    repository = channel_repository

    repository.add_member("#one", "Alice")
    repository.add_member("#two", "Alice")
    repository.add_member("#two", "Bob")

    repository.find_user_channel_names("Alice").sort.should eq(["#one", "#two"])
    repository.find_user_channels("Alice").map(&.name).sort.should eq(["#one", "#two"])
    repository.find_user_channel_names("Bob").should eq(["#two"])
  end

  it "removes user channel indexes on part and channel removal" do
    repository = channel_repository

    repository.add_member("#one", "Alice")
    repository.add_member("#two", "Alice")

    repository.part_user("#one", "Alice").should be_true
    repository.find_user_channel_names("Alice").should eq(["#two"])

    repository.remove("#two").should be_true
    repository.find_user_channel_names("Alice").should be_empty
  end

  it "removes a user from only indexed channels" do
    repository = channel_repository

    100.times do |index|
      repository.create_channel("#channel#{index}")
    end
    repository.add_member("#one", "Alice")
    repository.add_member("#two", "Alice")

    repository.remove_user_from_all_channels("Alice").sort.should eq(["#one", "#two"])
    repository.find_user_channel_names("Alice").should be_empty
  end

  it "renames indexed members without scanning unrelated channels" do
    repository = channel_repository

    repository.add_member("#one", "Alice")
    repository.add_member("#two", "Alice")
    repository.add_member("#other", "Bob")

    repository.rename_member("Alice", "Carol").sort.should eq(["#one", "#two"])
    repository.find_user_channel_names("Alice").should be_empty
    repository.find_user_channel_names("Carol").sort.should eq(["#one", "#two"])
    repository.get("#one").try(&.has_member?("Carol")).should be_true
    repository.get("#other").try(&.has_member?("Bob")).should be_true
  end
end
