# frozen_string_literal: true

require_relative "base_error"

module Errors
  class APIError < BaseError
    # Builds an API error with the project's default status and error code.
    #
    # @param message [String, nil] readable error message
    # @param status [Integer, Symbol] HTTP status for the response
    # @param code [String] stable machine-readable error code
    # @param detail [Object, nil] optional additional error details
    # @return [Errors::APIError]
    def initialize(message = nil, status: 500, code: "api_error", detail: nil)
      super
    end
  end
end
