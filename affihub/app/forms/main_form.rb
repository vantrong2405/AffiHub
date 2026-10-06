# frozen_string_literal: true

class MainForm
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations
  include ActiveModel::Validations::Callbacks

  attr_reader :params

  def valid!
    raise ::Errors::ResourceError.new(resource: self, message: errors.full_messages) unless valid?
    self
  end

  def attributes
    super.symbolize_keys
  end
end
