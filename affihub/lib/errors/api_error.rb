# frozen_string_literal: true

module Errors
  class APIError < StandardError
    attr_reader :status, :error_code, :details

    def initialize(message = nil, status: :unprocessable_entity, error_code: nil, details: {})
      @status = status
      @error_code = error_code
      @details = details
      super(message)
    end

    def to_hash
      { error: error_code || "API Error", message: message, details: details }
    end
  end
end
