# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let!(:user) { create(:user, email: "user@example.com", password: "password123") }

  describe "POST /login" do
    it "returns a redirect to the Dashboard and sets the session on correct credentials" do
      post "/login", params: { email: user.email, password: "password123" }

      expect(response).to redirect_to(root_path)
      expect(session[:user_id]).to eq(user.id)
    end

    it "returns 422 and leaves the session empty on wrong password" do
      post "/login", params: { email: user.email, password: "wrong" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(session[:user_id]).to eq(nil)
    end
  end

  describe "DELETE /logout" do
    it "returns a redirect to login and clears the session" do
      post "/login", params: { email: user.email, password: "password123" }

      delete "/logout"

      expect(session[:user_id]).to eq(nil)
      expect(response).to redirect_to(login_path)
    end
  end
end
