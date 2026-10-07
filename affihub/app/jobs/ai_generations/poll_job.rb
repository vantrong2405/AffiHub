# frozen_string_literal: true

class AiGenerations::PollJob < ApplicationJob
  CONFIGURATION = Rails.application.config_for(:money_printer_turbo).deep_symbolize_keys

  # Polls one saved MPT task and schedules another poll while it is incomplete.
  #
  # @param ai_generation_id [Integer] the generation whose task should be polled
  # @return [Boolean] whether another poll was scheduled
  def perform(ai_generation_id)
    service = AiGenerations::PollService.new(ai_generation_id:)
    service.call
    return false unless service.retry_poll?

    self.class.set(wait: CONFIGURATION.fetch(:poll_interval_seconds).seconds).perform_later(ai_generation_id)
    true
  end
end
