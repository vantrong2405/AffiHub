class Schedules::UpdateService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:schedule)
  ALLOWED_STATUSES = %w[active paused cancelled].freeze

  attr_reader :schedule

  # Initializes a Schedule update scoped to its owning project.
  #
  # @param video_project_id [Integer] the project that owns the Schedule
  # @param schedule_id [Integer] the Schedule to update
  # @param status [String, nil] the requested active, paused or cancelled state
  # @param scheduled_at [String, nil] a new local datetime for the pending occurrence
  # @param time_zone [String, nil] the timezone to save with the Schedule
  # @param recurrence [String, nil] the recurrence for future occurrences
  # @return [Schedules::UpdateService] the configured service
  def initialize(video_project_id:, schedule_id:, status: nil, scheduled_at: nil, time_zone: nil, recurrence: nil)
    @video_project_id = video_project_id
    @schedule_id = schedule_id
    @status_input = status.to_s
    @scheduled_at_input = scheduled_at
    @time_zone_input = time_zone
    @recurrence_input = recurrence.to_s
    super()
  end

  # Updates schedule details, pause state, or cancellation state.
  #
  # @return [Boolean] whether the Schedule update was applied
  def call
    return false unless step_load_schedule
    return false unless step_update_schedule

    step_succeed!
    success?
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  private

  def step_load_schedule
    @schedule = Schedule.joins(:render_version)
      .where(render_versions: { video_project_id: @video_project_id })
      .find_by(id: @schedule_id)
    return true if schedule

    step_fail!("Không tìm thấy lịch đăng trong project này.")
  end

  def step_update_schedule
    Schedule.transaction do
      @schedule.lock!
      target_status = @status_input.presence || schedule.status
      return step_fail!("Trạng thái lịch đăng không được hỗ trợ.") unless ALLOWED_STATUSES.include?(target_status)
      return false unless step_update_pending_occurrence

      case target_status
      when "cancelled"
        step_cancel_schedule
      when "paused"
        schedule.update!(status: :paused)
        return false unless step_skip_elapsed_occurrences
      when "active"
        if schedule.paused?
          return false unless step_skip_elapsed_occurrences
          return true if schedule.completed?
        end
        schedule.update!(status: :active)
      end
    end
    true
  end

  def step_update_pending_occurrence
    return true unless scheduling_attributes_submitted?

    occurrence = schedule.schedule_occurrences.scheduled.order(:scheduled_at, :id).first
    return step_fail!("Lịch không còn occurrence chờ để chỉnh sửa.") unless occurrence

    time_zone = ActiveSupport::TimeZone[@time_zone_input.presence || schedule.time_zone]
    return step_fail!("Timezone đã chọn không hợp lệ.") unless time_zone

    recurrence = @recurrence_input.presence || schedule.recurrence
    return step_fail!("Loại lịch không được hỗ trợ.") unless Schedule.recurrences.key?(recurrence)

    scheduled_at = if @scheduled_at_input.present?
      time_zone.parse(@scheduled_at_input.to_s)
    else
      schedule.next_occurrence_at&.in_time_zone(time_zone)
    end
    return step_fail!("Thời gian lập lịch không hợp lệ.") unless scheduled_at
    return step_fail!("Thời gian lập lịch phải nằm trong tương lai.") unless scheduled_at > Time.current

    occurrence_key = scheduled_at.utc.iso8601(6)
    key_taken = schedule.schedule_occurrences.where(occurrence_key:).where.not(id: occurrence.id).exists?
    return step_fail!("Lịch đã có occurrence tại thời điểm này.") if key_taken

    occurrence.update!(
      occurrence_key:,
      scheduled_at:,
      dispatch_at: scheduled_at + step_jitter_seconds.seconds
    )
    schedule.update!(
      recurrence:,
      time_zone: time_zone.name,
      local_time: scheduled_at.in_time_zone(time_zone).strftime("%H:%M:%S"),
      next_occurrence_at: scheduled_at
    )
    true
  rescue ArgumentError, TypeError
    step_fail!("Thời gian lập lịch không hợp lệ.")
  end

  def scheduling_attributes_submitted?
    @scheduled_at_input.present? || @time_zone_input.present? || @recurrence_input.present?
  end

  def step_skip_elapsed_occurrences
    occurrence_ids = schedule.schedule_occurrences.scheduled
      .where(scheduled_at: ..Time.current)
      .order(:scheduled_at, :id)
      .pluck(:id)
    occurrence_ids.each do |occurrence_id|
      service = Schedules::ProcessOccurrenceService.new(schedule_occurrence_id: occurrence_id)
      return step_fail!(service.errors.full_messages.to_sentence) unless service.call

      @schedule.reload
    end
    true
  end

  def step_cancel_schedule
    schedule.update!(status: :cancelled, next_occurrence_at: nil)
    schedule.schedule_occurrences.scheduled.find_each do |occurrence|
      occurrence.update!(status: :skipped, processed_at: Time.current)
    end
  end

  def step_jitter_seconds
    minimum = CONFIGURATION.fetch(:jitter_min_seconds).to_i
    maximum = CONFIGURATION.fetch(:jitter_max_seconds).to_i
    minimum + SecureRandom.random_number(maximum - minimum + 1)
  end
end
