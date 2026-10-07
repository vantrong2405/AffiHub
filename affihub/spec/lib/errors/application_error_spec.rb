# frozen_string_literal: true

require "rails_helper"

RSpec.describe Errors::ApplicationError, type: :lib do
  describe "#initialize" do
    it "stores the status, code, and details" do
      application_error = described_class.new(
        "Invalid request",
        status: :unprocessable_entity,
        error_code: "invalid_request",
        details: { field: "title" }
      )

      expect(application_error.message).to eq("Invalid request")
      expect(application_error.status).to eq(:unprocessable_entity)
      expect(application_error.error_code).to eq("invalid_request")
      expect(application_error.details).to eq(field: "title")
    end
  end

  describe "specialized errors" do
    it "uses not found status for a missing resource" do
      not_found_error = Errors::NotFoundError.new

      expect(not_found_error.status).to eq(:not_found)
    end

    it "uses unauthorized status for a missing authorization" do
      unauthorized_error = Errors::UnauthorizedError.new

      expect(unauthorized_error.status).to eq(:unauthorized)
    end

    it "uses forbidden status for a denied action" do
      forbidden_error = Errors::ForbiddenError.new

      expect(forbidden_error.status).to eq(:forbidden)
    end
  end
end
