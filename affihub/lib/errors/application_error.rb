# frozen_string_literal: true

module Errors
  class ApplicationError < StandardError
    attr_reader :status, :error_code, :details

    # Initializes an application error with response metadata.
    #
    # @param message [String, nil] the safe error message
    # @param status [Symbol] the HTTP status represented by the error
    # @param error_code [String, nil] the stable application error code
    # @param details [Hash] additional safe error details
    # @return [Errors::ApplicationError] the configured error
    def initialize(message = nil, status: :unprocessable_entity, error_code: nil, details: {})
      @status = status
      @error_code = error_code
      @details = details
      super(message)
    end
  end

  class NotFoundError < ApplicationError
    # Initializes an application error for a missing resource.
    #
    # @param message [String] the safe error message
    # @param options [Hash] additional application error metadata
    # @return [Errors::NotFoundError] the configured error
    def initialize(message = "Resource not found", **options)
      super(message, status: :not_found, **options)
    end
  end

  class UnauthorizedError < ApplicationError
    # Initializes an application error for a missing authorization.
    #
    # @param message [String] the safe error message
    # @param options [Hash] additional application error metadata
    # @return [Errors::UnauthorizedError] the configured error
    def initialize(message = "Unauthorized access", **options)
      super(message, status: :unauthorized, **options)
    end
  end

  class ForbiddenError < ApplicationError
    # Initializes an application error for a denied action.
    #
    # @param message [String] the safe error message
    # @param options [Hash] additional application error metadata
    # @return [Errors::ForbiddenError] the configured error
    def initialize(message = "Access forbidden", **options)
      super(message, status: :forbidden, **options)
    end
  end
end
