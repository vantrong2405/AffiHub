require "rails_helper"

RSpec.describe "Social connection pages", type: :request do
  let(:social_connection) { create(:social_connection) }

  describe "GET /social_connections" do
    it "returns the connected profile list" do
      get social_connections_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /social_connections/new" do
    it "returns the provider connection page" do
      get new_social_connection_path(provider: "facebook")

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /social_connections/:id" do
    it "returns the selected profile and its destinations" do
      create(:social_destination, social_connection:)

      get social_connection_path(social_connection)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /social_connections" do
    it "returns a redirect to Facebook authorization" do
      post social_connections_path, params: { provider: "facebook" }

      expect(URI(response.location).host).to eq("www.facebook.com")
    end
  end
end
