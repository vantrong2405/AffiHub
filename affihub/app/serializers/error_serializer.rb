# frozen_string_literal: true

class ErrorSerializer < ActiveModel::Serializer
  attributes :error, :message, :errors

  def error
    object.try(:error) || object.class.name.demodulize.underscore
  end

  def message
    object.try(:message) || object.to_s
  end

  def errors
    if object.respond_to?(:errors) && object.errors.respond_to?(:full_messages)
      object.errors.full_messages
    elsif object.try(:errors).is_a?(Array)
      object.errors
    else
      []
    end
  end
end
