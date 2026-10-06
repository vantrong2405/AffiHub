# frozen_string_literal: true

module Errors
  class BaseError < StandardError
    attr_reader :status, :code, :detail

    # Builds a structured error response for controller error handlers.
    #
    # @param message [String, nil] readable error message
    # @param status [Integer, Symbol, nil] HTTP status for the response
    # @param code [String, nil] stable machine-readable error code
    # @param detail [Object, nil] optional additional error details
    # @return [Errors::BaseError]
    def initialize(message = nil, status: nil, code: nil, detail: nil)
      @status = status
      @code = code
      @detail = detail

      super(message)
    end

    # Serializes the error fields used by the API error handler.
    #
    # @return [Hash]
    def to_hash
      {
        status: status,
        code: code,
        message: message,
        detail: detail
      }.compact
    end
  end
end
