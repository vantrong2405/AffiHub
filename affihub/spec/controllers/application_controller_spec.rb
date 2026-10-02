# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ApplicationController", type: :controller do
  controller(MainController) do
    before_action :require_login, only: :protected_action

    def protected_action
      render plain: "ok"
    end

    def show_current_user
      render plain: current_user&.email.to_s
    end
  end

  before do
    routes.draw do
      get "protected_action" => "main#protected_action"
      get "show_current_user" => "main#show_current_user"
    end
  end

  describe "#current_user" do
    it "returns the user matching session[:user_id]" do
      user = create(:user)
      session[:user_id] = user.id

      get :show_current_user

      expect(response.body).to eq(user.email)
    end

    it "returns nil when session[:user_id] is absent" do
      get :show_current_user

      expect(response.body).to eq("")
    end
  end

  describe "#require_login" do
    it "returns a redirect to login_path when current_user is nil" do
      get :protected_action

      expect(response).to redirect_to(login_path)
    end

    it "returns 200 when current_user is present" do
      user = create(:user)
      session[:user_id] = user.id

      get :protected_action

      expect(response).to have_http_status(:ok)
    end
  end
end
