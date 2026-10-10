require_relative "../config/environment"

RSpec.describe "Rails application boot" do
  it "loads the test environment" do
    expect(Rails.env).to eq("test")
  end
end
