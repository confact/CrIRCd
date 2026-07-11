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
    repository.find_user_channels("Alice").map(&.name).sort!.should eq(["#one", "#two"])
    traversed = [] of String
    repository.each_user_channel("Alice") { |channel| traversed << channel.name }
    traversed.sort!.should eq(["#one", "#two"])
    repository.find_user_channel_names("Bob").should eq(["#two"])
  end

  it "removes user channel indexes on part and channel removal" do
    repository = channel_repository

    repository.add_member("#one", "Alice")
    repository.add_member("#two", "Alice")

    repository.part_user("#one", "Alice").should be_true
    repository.find_user_channel_names("Alice").should eq(["#two"])

    repository.delete("#two").should_not be_nil
    repository.find_user_channel_names("Alice").should be_empty
  end

  it "removes a user from only indexed channels" do
    repository = channel_repository

    100.times do |index|
      repository.create_channel("#channel#{index}")
    end
    repository.add_member("#one", "Alice")
    repository.add_member("#two", "Alice")

    repository.remove_user_from_all_channels("Alice").to_a.sort!.should eq(["#one", "#two"])
    repository.find_user_channel_names("Alice").should be_empty
  end

  it "renames indexed members without scanning unrelated channels" do
    repository = channel_repository

    repository.add_member("#one", "Alice")
    repository.add_member("#two", "Alice")
    repository.add_member("#other", "Bob")

    repository.rename_member("Alice", "Carol").to_a.sort!.should eq(["#one", "#two"])
    repository.find_user_channel_names("Alice").should be_empty
    repository.find_user_channel_names("Carol").sort.should eq(["#one", "#two"])
    repository["#one"]?.try(&.has_member?("Carol")).should be_true
    repository["#other"]?.try(&.has_member?("Bob")).should be_true
  end

  it "uses IRC case mapping for channels and members" do
    repository = channel_repository

    repository.add_member("#Mixed[Case]", "Alice[One]")

    repository["#mIXED{cASE}"]?.try(&.name).should eq("#Mixed[Case]")
    repository.user_in_channel?("#MIXED{CASE}", "aLICE{oNE}").should be_true
    repository.find_user_channel_names("ALICE{ONE}").should eq(["#Mixed[Case]"])
    repository.part_user("#mixed{case}", "alice{one}").should be_true
    repository["#Mixed[Case]"]?.should be_nil
  end

  it "replaces channel membership indexes without losing display names" do
    repository = channel_repository
    repository.add_member("#Mixed", "Alice")
    replacement = Circed::Domain::Channel.new("#Mixed")
    replacement.add_member("Bob")

    repository["#mIXED"] = replacement

    repository.find_user_channel_names("Alice").should be_empty
    repository.find_user_channel_names("Bob").should eq(["#Mixed"])
    repository.remove_user_from_all_channels("bOB").should eq(Set{"#Mixed"})
    repository["#mixed"]?.should be_nil
  end

  it "renames members in display-cased channels" do
    repository = channel_repository
    repository.add_member("#Mixed", "Alice")

    repository.rename_member("aLICE", "Bob").should eq(Set{"#Mixed"})

    repository["#mixed"]?.try(&.has_member?("Alice")).should be_false
    repository["#mixed"]?.try(&.has_member?("Bob")).should be_true
  end
end
