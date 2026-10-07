class Publications::ConfirmService < ApplicationService
  # The project that owns the approved Publication.
  # @return [VideoProject]
  attr_reader :video_project

  attr_reader :publication, :workflow_run

  # Initializes confirmation of one project draft after its destination passes preflight.
  #
  # @param video_project_id [Integer] the project that owns the Publication
  # @param publication_id [Integer] the draft approved for publication
  # @param preflight_report_id [Integer] the report used to verify readiness
  # @return [Publications::ConfirmService] the configured service
  def initialize(video_project_id:, publication_id:, preflight_report_id:)
    @video_project_id = video_project_id
    @publication_id = publication_id
    @preflight_report_id = preflight_report_id
    super()
  end

  # Approves the reviewed draft and queues its publication workflow.
  #
  # @return [Boolean] whether the publication workflow was queued
  def call
    return false unless step_approve_publication

    step_enqueue_publish_job
    step_succeed!
    success?
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  private

  def step_approve_publication
    Publication.transaction do
      @video_project = VideoProject.find(@video_project_id)
      @publication = video_project.publications.lock.find(@publication_id)
      return step_fail!("Chỉ được xác nhận Publication ở trạng thái bản nháp.") unless publication.draft?

      @preflight_report = publication.render_version.preflight_reports.recent_first.first
      return step_fail!("Không tìm thấy báo cáo preflight.") unless @preflight_report
      return step_fail!("Báo cáo preflight đã thay đổi. Hãy tải lại trang review.") unless latest_report_selected?
      return step_fail!("Destination không sẵn sàng theo báo cáo preflight.") unless destination_ready?

      step_create_workflow_run
      publication.update!(status: :approved)
    end
  end

  def step_create_workflow_run
    @workflow_run = publication.workflow_runs.create!(
      operation_id: "publication-#{publication.id}-publish",
      operation: "publication_publish",
      stage: "publish",
      status: :queued
    )
  end

  def step_enqueue_publish_job
    Publications::PublishJob.perform_later(workflow_run.id)
  end

  def destination_ready?
    @preflight_report.ready_for?(
      render_version: publication.render_version,
      social_destination: publication.social_destination
    )
  end

  def latest_report_selected?
    @preflight_report.id.to_s == @preflight_report_id.to_s
  end
end
