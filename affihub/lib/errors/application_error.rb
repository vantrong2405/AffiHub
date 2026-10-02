# frozen_string_literal: true

class Errors::ApplicationError < StandardError
  attr_reader :status, :error_code, :details

  def initialize(message = nil, status: :unprocessable_entity, error_code: nil, details: {})
    @status = status
    @error_code = error_code
    @details = details
    super(message)
  end
end

class Errors::NotFoundError < Errors::ApplicationError
  def initialize(message = "Resource not found", **options)
    super(message, status: :not_found, **options)
  end
end

class Errors::UnauthorizedError < Errors::ApplicationError
  def initialize(message = "Unauthorized access", **options)
    super(message, status: :unauthorized, **options)
  end
end

class Errors::ForbiddenError < Errors::ApplicationError
  def initialize(message = "Access forbidden", **options)
    super(message, status: :forbidden, **options)
  end
end
