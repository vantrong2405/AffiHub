# frozen_string_literal: true

class MainOperation
  attr_reader :params, :current_user, :form, :errors

  class << self
    def call(*args)
      itself = new(*args)
      itself.call
      itself
    end
  end

  def initialize(params:)
    @params       = params || {}
    @current_user = params[:current_user]
  end

  def call
    # Subclasses should override this method
    raise NotImplementedError, "#{self.class} must implement #call"
  end

  def success?
    @errors.empty?
  end

  def error?
    !success?
  end

  def errors
    @errors ||= @form.errors
  end

  private

  def step_validate
    # Subclasses should override this method
    raise NotImplementedError, "#{self.class} must implement #step_validate"
  end
end
