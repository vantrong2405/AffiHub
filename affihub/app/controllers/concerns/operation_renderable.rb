# frozen_string_literal: true

module OperationRenderable
  extend ActiveSupport::Concern

  def render_operation(operator, success:, failure: nil, notice: nil, alert: nil)
    if operator.success?
      redirect_to success, notice: notice
    else
      flash.now[:alert] = alert || operator.errors.full_messages.to_sentence
      render (failure || default_action_for(action_name)), status: :unprocessable_entity
    end
  end

  private

  def default_action_for(current_action_name)
    case current_action_name
    when "create" then :new
    when "update" then :edit
    else current_action_name.to_sym
    end
  end
end
