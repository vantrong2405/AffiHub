# frozen_string_literal: true

module Errors
  class ResourceError < StandardError
    attr_reader :resource, :errors, :status

    def initialize(resource:, message: nil, status: 422)
      @resource = resource
      @status = status

      # Set errors from message or resource
      @errors = if message.is_a?(Array)
                  message
                elsif message.present?
                  [message]
                elsif resource.respond_to?(:errors) && resource.errors.any?
                  resource.errors.full_messages
                else
                  []
                end

      super(@errors.first || "Error with resource #{resource.class.name}")
    end
  end
end
