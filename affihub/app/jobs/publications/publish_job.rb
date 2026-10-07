class Publications::PublishJob < ApplicationJob
  queue_as :default

  # Runs the persisted publication workflow outside the web request.
  #
  # @param workflow_run_id [Integer] the workflow run to publish
  # @return [Boolean] whether the publisher completed successfully
  def perform(workflow_run_id)
    Publications::MetaGraphPublisher.new(workflow_run_id:).call
  end
end
