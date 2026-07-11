require "../../spec_helper"

describe Circed::Domain::CaseMapping do
  it "folds ASCII letters and RFC1459 nickname equivalents" do
    Circed::Domain::CaseMapping.normalize("AZ[]\\~").should eq("az{}|^")
  end

  it "reuses strings that are already normalized" do
    name = "normalized{}|^"

    Circed::Domain::CaseMapping.normalize(name).same?(name).should be_true
  end

  it "compares names using RFC1459 casemapping" do
    Circed::Domain::CaseMapping.same?("Nick[Name]", "nICK{name}").should be_true
    Circed::Domain::CaseMapping.same?("Nick", "Other").should be_false
  end

  it "applies RFC1459 equivalence to wildcard matching" do
    Circed::Domain::Wildcard.match?("Nick[*", "nICK{value").should be_true
  end
end
