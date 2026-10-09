class Schedules::SchedulerService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:schedule)

  attr_reader :processed_occurrence_ids, :enqueued_workflow_run_ids

  # Initializes one Scheduler scan for due occurrences and queued publications.
  #
  # @return [Schedules::SchedulerService] the configured service
  def initialize
    @processed_occurrence_ids = []
    @enqueued_workflow_run_ids = []
    super()
  end

  # Processes due occurrences and recovers queued publication jobs after an enqueue gap.
  #
  # @return [Boolean] whether the scan completed
  def call
    return false unless step_enqueue_queued_publications
    return false unless step_process_due_occurrences

    step_succeed!
    success?
  end

  private

  def step_process_due_occurrences
    due_occurrences = ScheduleOccurrence.scheduled.where(dispatch_at: ..Time.current).order(:dispatch_at, :id)
    due_occurrences.find_each do |schedule_occurrence|
      service = Schedules::ProcessOccurrenceService.new(schedule_occurrence_id: schedule_occurrence.id)
      service.call
      @processed_occurrence_ids << schedule_occurrence.id
    end
    true
  end

  def step_enqueue_queued_publications
    queued_publication_workflows.find_each do |workflow_run|
      job = Publications::PublishJob.perform_later(workflow_run.id)
      return step_fail!("Không thể khôi phục Publication workflow vào hàng đợi.") unless job&.successfully_enqueued?

      @enqueued_workflow_run_ids << workflow_run.id
    end
    true
  end

  def queued_publication_workflows
    WorkflowRun.where(
      workflowable_type: "Publication",
      operation: CONFIGURATION.fetch(:scheduler_operation),
      stage: CONFIGURATION.fetch(:scheduler_stage),
      status: :queued
    ).order(:created_at, :id)
  end
end
