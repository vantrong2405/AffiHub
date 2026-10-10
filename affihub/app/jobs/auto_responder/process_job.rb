class AutoResponder::ProcessJob < ApplicationJob
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:auto_responder)

  queue_as :default

  # Processes one queued workflow for a public comment reply.
  #
  # @param workflow_run_id [Integer] the persisted workflow to process
  # @return [Boolean] whether Meta confirmed the reply
  def perform(workflow_run_id)
    worker_id = "#{CONFIGURATION.fetch(:worker_id_prefix)}-#{SecureRandom.uuid}"
    AutoResponder::ProcessService.new(workflow_run_id:, worker_id:).call
  end
end
