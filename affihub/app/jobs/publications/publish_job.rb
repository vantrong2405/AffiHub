class Publications::PublishJob < ApplicationJob
  queue_as :default

  # Runs the persisted publication workflow outside the web request.
  #
  # @param workflow_run_id [Integer] the workflow run to publish
  # @return [Boolean] whether the publisher completed successfully
  def perform(workflow_run_id)
    workflow_run = WorkflowRun.includes(:workflowable).find_by(id: workflow_run_id)
    return false unless workflow_run&.workflowable.is_a?(Publication)
    return false if step_auto_publish_paused?(workflow_run.workflowable)

    resolver = Publications::PublisherResolver.new(
      provider: workflow_run.workflowable.social_destination.provider
    )
    return false unless resolver.call

    resolver.publisher_class.new(workflow_run_id:).call
  end

  private

  def step_auto_publish_paused?(publication)
    publication.schedule_occurrence_id.present? && AutomationControl.current.auto_publish_paused?
  end
end
