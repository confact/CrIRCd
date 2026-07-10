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
    client.socket.as(DummySocket).sent_data.join.should contain(
      " 005 Alice CASEMAPPING=rfc1459 CHANTYPES=#&+! PREFIX=(ohv)@%+ CHANMODES=b,k,l,imnpst NICKLEN=30 :are supported by this server"
    )
  end

  it "reports the current IRC operator count in LUSERS" do
    alice = create_test_client("Alice")
    create_test_client("Bob")
    user_repository["Alice"]?.try { |user| user.modes << 'o' }
    user_repository["Bob"]?.try { |user| user.modes << 'i' }

    response = Circed::Server.lusers(alice)
    response.should contain(" 251 Alice :There are 1 users and 1 invisible on 1 server(s)")
    response.should contain(" 252 Alice 1 :IRC Operators online")
    response.should contain(" 253 Alice 0 :unregistered connections")
    response.should contain(" 254 Alice 0 :channels formed")
  end

  it "formats MOTD as one buffered IRC response" do
    response = Circed::Server.motd(create_test_client("Alice"))

    response.lines.size.should eq(3)
    response.should contain(" 375 Alice :- localhost Message of the day -")
    response.should contain(" 372 Alice :- Welcome to Circd Server")
    response.should contain(" 376 Alice :End of MOTD command")
  end
end
