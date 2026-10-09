class Schedules::ProcessOccurrenceService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys
  SCHEDULE_CONFIGURATION = CONFIGURATION.fetch(:schedule)
  PUBLICATION_CONFIGURATION = CONFIGURATION.fetch(:publication_workflow)

  attr_reader :occurrence, :preflight_report, :publications

  # Initializes processing for one persisted Schedule occurrence.
  #
  # @param schedule_occurrence_id [Integer] the scheduled occurrence to process
  # @return [Schedules::ProcessOccurrenceService] the configured service
  def initialize(schedule_occurrence_id:)
    @schedule_occurrence_id = schedule_occurrence_id
    @publications = []
    @workflow_run_ids = []
    super()
  end

  # Dispatches an occurrence only inside its jitter window and current preflight state.
  #
  # @return [Boolean] whether the occurrence was processed or already terminal
  def call
    return false unless step_load_occurrence
    return step_succeed_without_work if occurrence_not_pending?
    if (occurrence.schedule.paused? || occurrence.schedule.cancelled?) && occurrence.scheduled_at <= Time.current
      return step_finish_without_publish(:skipped)
    end
    return step_fail!("Lịch chưa tới thời điểm gửi.") if Time.current < occurrence.dispatch_at
    return step_finish_without_publish(:skipped) if occurrence.schedule.paused? || occurrence.schedule.cancelled?
    return step_finish_without_publish(:missed) if step_execution_window_expired?
    unless step_load_preflight_report
      step_close_preflight_failure
      return step_fail!(@preflight_failure_message)
    end

    return false unless step_dispatch_occurrence
    return false unless step_enqueue_publications

    step_succeed!
    success?
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  private

  def step_load_occurrence
    @occurrence = ScheduleOccurrence.includes(:schedule, :preflight_report).find_by(id: @schedule_occurrence_id)
    return true if occurrence

    step_fail!("Không tìm thấy Schedule occurrence cần xử lý.")
  end

  def occurrence_not_pending?
    !occurrence.scheduled?
  end

  def step_succeed_without_work
    step_succeed!
    success?
  end

  def step_execution_window_expired?
    latest_execution_at = occurrence.scheduled_at + SCHEDULE_CONFIGURATION.fetch(:max_execution_window_seconds).to_i.seconds
    Time.current > latest_execution_at
  end

  def step_load_preflight_report
    service = PreflightReports::CreateService.new(
      video_project_id: occurrence.schedule.render_version.video_project_id,
      render_version_id: occurrence.schedule.render_version_id,
      social_destination_ids: occurrence.schedule.schedule_destinations.map(&:social_destination_id)
    )
    unless service.call
      @preflight_failure_message = service.errors.full_messages.to_sentence.presence ||
        "Không thể kiểm tra preflight trước khi đăng theo lịch."
      return false
    end

    @preflight_report = service.preflight_report
    if preflight_report
      true
    else
      @preflight_failure_message = "Preflight không tạo được báo cáo mới cho Schedule occurrence."
      false
    end
  end

  def step_close_preflight_failure
    ScheduleOccurrence.transaction do
      @occurrence = ScheduleOccurrence.lock.includes(:schedule).find(@occurrence.id)
      if occurrence.scheduled?
        status = if occurrence.schedule.paused? || occurrence.schedule.cancelled?
          :skipped
        elsif step_execution_window_expired?
          :missed
        else
          :failed
        end
        safe_error_code = if status == :failed
          PUBLICATION_CONFIGURATION.fetch(:safe_error_codes).fetch(:schedule_preflight_failed)
        end
        step_update_occurrence_status(status, safe_error_code:)
        step_advance_schedule
      end
    end
  end

  def step_dispatch_occurrence
    ScheduleOccurrence.transaction do
      @occurrence = ScheduleOccurrence.lock.includes(:schedule).find(@occurrence.id)
      if occurrence_not_pending?
        true
      elsif occurrence.schedule.paused? || occurrence.schedule.cancelled?
        step_update_occurrence_status(:skipped)
        step_advance_schedule
      elsif step_execution_window_expired?
        step_update_occurrence_status(:missed)
        step_advance_schedule
      else
        @occurrence.update!(preflight_report:)
        step_create_publications
        @occurrence.update!(status: :dispatched, processed_at: Time.current)
        step_advance_schedule
      end
    end

    true
  end

  def step_create_publications
    occurrence.schedule.schedule_destinations.includes(:social_destination).order(:id).each do |schedule_destination|
      ready = preflight_report.ready_for?(
        render_version: occurrence.schedule.render_version,
        social_destination: schedule_destination.social_destination
      )
      publication = occurrence.publications.create!(
        render_version: occurrence.schedule.render_version,
        social_destination: schedule_destination.social_destination,
        caption: schedule_destination.caption,
        scheduled_at: occurrence.scheduled_at,
        schedule_occurrence_key: "#{occurrence.occurrence_key}:#{schedule_destination.social_destination_id}",
        status: ready ? :approved : :failed,
        safe_error_code: ready ? nil : PUBLICATION_CONFIGURATION.fetch(:safe_error_codes).fetch(:schedule_preflight_blocked)
      )
      @publications << publication
      step_create_publish_workflow(publication, schedule_destination) if ready
    end
  end

  def step_create_publish_workflow(publication, schedule_destination)
    publication.update!(consent_snapshot: step_bound_consent_snapshot(publication, schedule_destination))
    workflow_run = publication.workflow_runs.create!(
      operation_id: "publication-#{publication.id}-publish",
      operation: PUBLICATION_CONFIGURATION.fetch(:operation),
      stage: PUBLICATION_CONFIGURATION.fetch(:publish_stage),
      status: :queued
    )
    @workflow_run_ids << workflow_run.id
  end

  def step_bound_consent_snapshot(publication, schedule_destination)
    snapshot = schedule_destination.consent_snapshot.to_h.stringify_keys
    case publication.social_destination.provider
    when "tiktok"
      snapshot.merge(
        "tiktok_schedule_id" => occurrence.schedule_id,
        "tiktok_render_version_id" => publication.render_version_id,
        "tiktok_publication_id" => publication.id
      )
    when "youtube"
      snapshot.merge(
        "render_version_id" => publication.render_version_id,
        "publication_id" => publication.id
      )
    else
      snapshot
    end
  end

  def step_enqueue_publications
    @workflow_run_ids.each do |workflow_run_id|
      job = Publications::PublishJob.perform_later(workflow_run_id)
      return step_fail!("Không thể đưa Publication vào hàng đợi.") unless job&.successfully_enqueued?
    end
    true
  end

  def step_finish_without_publish(status)
    ScheduleOccurrence.transaction do
      @occurrence = ScheduleOccurrence.lock.includes(:schedule).find(occurrence.id)
      if occurrence.scheduled?
        step_update_occurrence_status(status)
        step_advance_schedule
      end
    end
    step_succeed!
    success?
  end

  def step_update_occurrence_status(status, safe_error_code: nil)
    occurrence.update!(status:, safe_error_code:, processed_at: Time.current)
  end

  def step_advance_schedule
    schedule = occurrence.schedule
    return if schedule.cancelled?

    if schedule.once?
      schedule.update!(status: :completed, next_occurrence_at: nil)
      return
    end

    next_occurrence_at = step_next_occurrence_at(schedule, occurrence.scheduled_at)
    schedule.update!(next_occurrence_at:)
    schedule.schedule_occurrences.create!(
      occurrence_key: next_occurrence_at.utc.iso8601(6),
      scheduled_at: next_occurrence_at,
      dispatch_at: next_occurrence_at + step_jitter_seconds.seconds
    )
  end

  def step_next_occurrence_at(schedule, previous_occurrence_at)
    time_zone = ActiveSupport::TimeZone[schedule.time_zone]
    previous_local_occurrence = previous_occurrence_at.in_time_zone(time_zone)
    next_occurrence_at = if schedule.daily?
      previous_local_occurrence.advance(days: 1)
    else
      previous_local_occurrence.advance(weeks: 1)
    end

    while next_occurrence_at <= Time.current
      next_occurrence_at = schedule.daily? ? next_occurrence_at.advance(days: 1) : next_occurrence_at.advance(weeks: 1)
    end

    next_occurrence_at
  end

  def step_jitter_seconds
    minimum = SCHEDULE_CONFIGURATION.fetch(:jitter_min_seconds).to_i
    maximum = SCHEDULE_CONFIGURATION.fetch(:jitter_max_seconds).to_i
    minimum + SecureRandom.random_number(maximum - minimum + 1)
  end
end
