# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  it "returns true for valid? with an email and password" do
    expect(user.valid?).to eq(true)
  end

  it "returns false for valid? without an email" do
    user.email = nil
    expect(user.valid?).to eq(false)
  end

  it "returns false for valid? when the email is already taken" do
    create(:user, email: "taken@example.com")
    user.email = "taken@example.com"

    expect(user.valid?).to eq(false)
  end

  it "returns the user from authenticate with the correct password" do
    user.save!
    expect(user.authenticate("password123")).to eq(user)
  end

  it "returns false from authenticate with the wrong password" do
    user.save!
    expect(user.authenticate("wrong")).to eq(false)
  end

  it "returns the associated AIConnection through the ai_connection association" do
    user.save!
    ai_connection = create(:ai_connection, user: user)

    expect(user.reload.ai_connection).to eq(ai_connection)
  end
end
