# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AffiliateConnections", type: :request do
  let(:user) { create(:user) }

  before { post "/login", params: { email: user.email, password: "password123" } }

  describe "GET /affiliate_connection/new" do
    it "returns success for the authenticated API token form" do
      get "/affiliate_connection/new"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /affiliate_connection" do
    it "creates the current user's encrypted ACCESSTRADE connection and redirects" do
      expect do
        post "/affiliate_connection", params: { affiliate_connection: { api_key: "secret-token" } }
      end.to change(AffiliateConnection, :count).by(1)

      connection = AffiliateConnection.find_by!(user: user)
      expect(response).to redirect_to(new_affiliate_connection_path)
      expect(connection.provider).to eq("accesstrade")
      expect(connection.api_key).to eq("secret-token")
      expect(flash[:notice]).to eq("ACCESSTRADE API token saved")
    end

    it "returns 422 and does not create a connection without an API token" do
      expect do
        post "/affiliate_connection", params: { affiliate_connection: { api_key: "" } }
      end.not_to change(AffiliateConnection, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
