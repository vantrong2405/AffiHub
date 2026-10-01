# frozen_string_literal: true

module Errorable
  extend ActiveSupport::Concern

  included do
    rescue_from StandardError, with: :handle_standard_error
    rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :handle_validation_error
    rescue_from ::Errors::ResourceError, with: :handle_resource_error
    rescue_from ::Errors::APIError, with: :handle_api_error
  end

  private

  def handle_standard_error(error)
    Rails.logger.error("#{error.class}: #{error.message}")
    Rails.logger.error(error.backtrace.join("\n"))

    render json: {
      error: 'Internal Server Error',
      message: 'Something went wrong'
    }, status: :internal_server_error
  end

  def handle_not_found(error)
    render json: {
      error: 'Not Found',
      message: error.message
    }, status: :not_found
  end

  def handle_validation_error(error)
    render json: {
      error: 'Validation Failed',
      message: error.message,
      errors: error.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  def handle_resource_error(error)
    render json: {
      error: 'Resource Error',
      message: error.message,
      resource: error.resource.class.name,
      errors: error.errors
    }, status: :unprocessable_entity
  end

  def handle_api_error(error)
    render json: error.to_hash, status: error.status || :unprocessable_entity
  end
end
