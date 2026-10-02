# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  let(:user) { create(:user) }

  describe "GET /" do
    it "redirects to login when the user is not authenticated" do
      get "/"

      expect(response).to redirect_to(login_path)
    end

    it "returns the dashboard for the authenticated user" do
      post "/login", params: { email: user.email, password: "password123" }

      get "/"

      expect(response).to have_http_status(:ok)
    end
  end
end
