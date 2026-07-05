require "../spec_helper"

describe Circed::Server do
  # Tests for server functionality

  before_each do
    clear_repositories
  end

  after_each do
    clear_repositories
  end

  it "should return name" do
    Circed::Server.name.should eq("localhost")
  end

  it "should return port" do
    Circed::Server.address.should eq(":localhost")
  end

  it "should return clean_name with :" do
    Circed::Server.clean_name.should eq(":localhost")
  end

  it "advertises implemented user and channel modes in MYINFO" do
    client = create_test_client("Alice")

    Circed::Server.welcome_message(client)

    client.socket.as(DummySocket).sent_data.join.should contain(" 004 Alice localhost ")
    client.socket.as(DummySocket).sent_data.join.should contain(" iwoO biklmnopsthv")
  end

  it "reports the current IRC operator count in LUSERS" do
    alice = create_test_client("Alice")
    create_test_client("Bob")
    user_repository.get("Alice").try { |user| user.modes << 'o' }
    user_repository.get("Bob").try { |user| user.modes << 'i' }

    response = Circed::Server.lusers(alice)
    response.should contain(" 251 Alice :There are 1 users and 1 invisible on 1 server(s)")
    response.should contain(" 252 Alice :1 IRC Operators online")
  end
end
