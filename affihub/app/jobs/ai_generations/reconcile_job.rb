# frozen_string_literal: true

class AiGenerations::ReconcileJob < ApplicationJob
  queue_as :default

  # Reconciles one saved MPT submission without creating a replacement task.
  #
  # @param ai_generation_id [Integer] the generation whose MPT submission is unresolved
  # @return [Boolean] whether the saved MPT submission was reconciled
  def perform(ai_generation_id)
    AiGenerations::SubmitService.new(ai_generation_id:).call
  end
end
