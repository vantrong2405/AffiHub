class WorkflowRuns::SweepJob < ApplicationJob
  queue_as :default

  # Recovers workflow runs whose worker lease has expired.
  #
  # @return [Boolean] whether expired workflow runs were swept
  def perform
    WorkflowRuns::SweepService.new.call
  end
end
