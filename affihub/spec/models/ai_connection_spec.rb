# frozen_string_literal: true

require "rails_helper"

RSpec.describe AIConnection, type: :model do
  subject(:ai_connection) { build(:ai_connection) }

  it "returns true for valid? with a user and required attributes" do
    expect(ai_connection.valid?).to eq(true)
  end

  it "returns :belongs_to for the user association" do
    expect(AIConnection.reflect_on_association(:user).macro).to eq(:belongs_to)
  end

  it "returns false for valid? when the user already has an AIConnection" do
    user = create(:user)
    create(:ai_connection, user: user)

    duplicate = build(:ai_connection, user: user)

    expect(duplicate.valid?).to eq(false)
  end

  it "stores access_token as ciphertext in the database" do
    ai_connection.save!

    raw_value = AIConnection.connection.select_value(
      "SELECT access_token FROM ai_connections WHERE id = #{ai_connection.id}"
    )

    expect(raw_value).not_to eq("access-token-value")
  end

  it "returns the decrypted access_token through the model" do
    ai_connection.save!
    ai_connection.reload

    expect(ai_connection.access_token).to eq("access-token-value")
  end

  it "returns 'connected' as a valid status enum value" do
    ai_connection.status = "connected"
    expect(ai_connection.valid?).to eq(true)
  end

  it "returns 'disconnected' as a valid status enum value" do
    ai_connection.status = "disconnected"
    expect(ai_connection.valid?).to eq(true)
  end

  it "stores id_token as ciphertext in the database" do
    ai_connection.id_token = "id-token-value"
    ai_connection.save!

    raw_value = AIConnection.connection.select_value(
      "SELECT id_token FROM ai_connections WHERE id = #{ai_connection.id}"
    )

    expect(raw_value).not_to eq("id-token-value")
  end

  it "returns the decrypted id_token through the model" do
    ai_connection.id_token = "id-token-value"
    ai_connection.save!
    ai_connection.reload

    expect(ai_connection.id_token).to eq("id-token-value")
  end

  it "stores chatgpt_account_id as plaintext (not encrypted, not sensitive)" do
    ai_connection.chatgpt_account_id = "acct-123"
    ai_connection.save!

    raw_value = AIConnection.connection.select_value(
      "SELECT chatgpt_account_id FROM ai_connections WHERE id = #{ai_connection.id}"
    )

    expect(raw_value).to eq("acct-123")
  end

  it "stores chatgpt_plan_type as plaintext (not encrypted, not sensitive)" do
    ai_connection.chatgpt_plan_type = "pro"
    ai_connection.save!

    raw_value = AIConnection.connection.select_value(
      "SELECT chatgpt_plan_type FROM ai_connections WHERE id = #{ai_connection.id}"
    )

    expect(raw_value).to eq("pro")
  end

  describe "#ensure_fresh_token!" do
    it "does nothing when access_token_expires_at is still far in the future" do
      ai_connection.access_token_expires_at = 1.hour.from_now
      ai_connection.save!

      ai_connection.ensure_fresh_token!

      expect(a_request(:post, "https://auth.openai.com/oauth/token")).not_to have_been_made
    end

    it "refreshes when access_token_expires_at is nil" do
      ai_connection.access_token_expires_at = nil
      ai_connection.save!
      stub_request(:post, "https://auth.openai.com/oauth/token").to_return(
        status: 200,
        body: { access_token: "a2", refresh_token: "r2", expires_in: 3600 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      ai_connection.ensure_fresh_token!
      ai_connection.reload

      expect(ai_connection.access_token).to eq("a2")
    end

    it "refreshes when access_token_expires_at is within the 10-minute lead window" do
      ai_connection.access_token_expires_at = 5.minutes.from_now
      ai_connection.save!
      stub_request(:post, "https://auth.openai.com/oauth/token").to_return(
        status: 200,
        body: { access_token: "a3", refresh_token: "r3", expires_in: 3600 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      ai_connection.ensure_fresh_token!
      ai_connection.reload

      expect(ai_connection.access_token).to eq("a3")
    end

    it "refreshes with the provider contract passed by the caller" do
      provider_class = Class.new(AIProviders::Contract) do
        attr_reader :received_refresh_token

        def refresh_lead
          15.minutes
        end

        def refresh_token(refresh_token:)
          @received_refresh_token = refresh_token
          { "access_token" => "alternate-access-token", "refresh_token" => "alternate-refresh-token", "expires_in" => 3600 }
        end
      end
      provider = provider_class.new
      ai_connection.access_token_expires_at = 11.minutes.from_now
      ai_connection.save!

      ai_connection.ensure_fresh_token!(provider: provider)
      ai_connection.reload

      expect(provider.received_refresh_token).to eq("refresh-token-value")
      expect(ai_connection.access_token).to eq("alternate-access-token")
      expect(ai_connection.refresh_token).to eq("alternate-refresh-token")
      expect(a_request(:post, "https://auth.openai.com/oauth/token")).not_to have_been_made
    end

    it "raises AIConnection::DisconnectedError and does not return silently when refresh fails" do
      ai_connection.access_token_expires_at = nil
      ai_connection.save!
      stub_request(:post, "https://auth.openai.com/oauth/token").to_return(status: 400, body: { error: "invalid_grant" }.to_json)

      expect { ai_connection.ensure_fresh_token! }.to raise_error(AIConnection::DisconnectedError)
    end
  end
end
