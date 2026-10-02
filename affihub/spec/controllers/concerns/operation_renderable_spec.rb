# frozen_string_literal: true

require "rails_helper"

FakeOperator = Struct.new(:success, :messages) do
  def success?
    success
  end

  def errors
    ActiveModel::Errors.new(self).tap do |e|
      messages.each { |m| e.add(:base, m) }
    end
  end
end

RSpec.describe "OperationRenderable", type: :controller do
  render_views

  controller(MainController) do
    layout false

    def create
      render_operation(@operator, success: "/success-path", notice: "Created!")
    end

    def update
      render_operation(@operator, success: "/success-path", notice: "Updated!")
    end

    def custom_action
      render_operation(@operator, success: "/success-path", failure: :edit, alert: "Custom alert")
    end
  end

  before do
    controller.prepend_view_path(Rails.root.join("spec/fixtures/views"))
    routes.draw do
      post "create" => "main#create"
      patch "update" => "main#update"
      post "custom_action" => "main#custom_action"
    end
  end

  def set_operator(success:, messages: [])
    controller.instance_variable_set(:@operator, FakeOperator.new(success, messages))
  end

  context "when the operation succeeds" do
    it "returns a redirect to success with flash notice" do
      set_operator(success: true)

      post :create

      expect(response).to redirect_to("/success-path")
      expect(flash[:notice]).to eq("Created!")
    end
  end

  context "when the operation fails on create" do
    it "returns 422, renders :new, flash alert from operator errors" do
      set_operator(success: false, messages: [ "Name can't be blank" ])

      post :create

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash.now[:alert]).to eq("Name can't be blank")
      expect(response.body).to eq("NEW_TEMPLATE")
    end
  end

  context "when the operation fails on update" do
    it "returns 422 and renders :edit" do
      set_operator(success: false, messages: [ "Invalid" ])

      patch :update

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to eq("EDIT_TEMPLATE")
    end
  end

  context "when a failure action and alert are explicitly given" do
    it "returns 422, renders the given action, with the given alert" do
      set_operator(success: false, messages: [ "ignored" ])

      post :custom_action

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash.now[:alert]).to eq("Custom alert")
      expect(response.body).to eq("EDIT_TEMPLATE")
    end
  end
end
