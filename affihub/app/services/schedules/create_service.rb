class Schedules::CreateService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:schedule)

  attr_reader :schedule, :occurrence, :time_zone, :rejected_destination_ids

  # Initializes a recurring or one-time schedule from a reviewed preflight report.
  #
  # @param video_project_id [Integer] the project that owns the selected render
  # @param render_version_id [Integer] the immutable render version to schedule
  # @param preflight_report_id [Integer] the report used to verify destinations
  # @param scheduled_at [String, Time] the selected local date and time
  # @param time_zone [String, nil] the selected timezone or the machine-local timezone
  # @param recurrence [String, Symbol] once, daily, or weekly
  # @param destination_settings [Hash] caption and consent snapshot keyed by destination ID
  # @return [Schedules::CreateService] the configured service
  def initialize(video_project_id:, render_version_id:, preflight_report_id:, scheduled_at:, recurrence:,
                 destination_settings:, time_zone: nil)
    @video_project_id = video_project_id
    @render_version_id = render_version_id
    @preflight_report_id = preflight_report_id
    @scheduled_at_input = scheduled_at
    @time_zone_input = time_zone
    @recurrence_input = recurrence.to_s
    @destination_settings = destination_settings.to_h.stringify_keys.transform_values do |settings|
      settings.to_h.stringify_keys
    end
    @rejected_destination_ids = []
    super()
  end

  # Creates a Schedule, destination snapshots, and the first jittered occurrence.
  #
  # @return [Boolean] whether a schedule and its initial occurrence were created
  def call
    return false unless step_load_video_project
    return false unless step_load_render_version
    return false unless step_load_preflight_report
    return false unless step_load_destinations
    return false unless step_load_schedule_time

    step_create_schedule
    step_enqueue_sheet_syncs
    step_enqueue_drive_exports
    step_succeed!
    success?
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find_by(id: @video_project_id)
    return true if @video_project

    step_fail!("Không tìm thấy Video Project cần lập lịch.")
  end

  def step_load_render_version
    @render_version = @video_project.render_versions.find_by(id: @render_version_id)
    return true if @render_version

    step_fail!("Không tìm thấy render version cần lập lịch.")
  end

  def step_load_preflight_report
    @preflight_report = @render_version.preflight_reports.find_by(id: @preflight_report_id)
    return step_fail!("Không tìm thấy báo cáo preflight đã chọn.") unless @preflight_report
    return true if @preflight_report.render_version_id == @render_version.id

    step_fail!("Báo cáo preflight không thuộc render version đã chọn.")
  end

  def step_load_destinations
    destination_ids = @destination_settings.keys.map(&:to_i)
    @social_destinations = SocialDestination.includes(:social_connection)
      .where(id: destination_ids)
      .index_by(&:id)
    return step_fail!("Có destination không tồn tại.") unless @social_destinations.size == destination_ids.uniq.size

    @social_destinations = destination_ids.map { |id| @social_destinations.fetch(id) }
    @rejected_destination_ids = @social_destinations.reject do |social_destination|
      @preflight_report.ready_for?(render_version: @render_version, social_destination:)
    end.map(&:id)
    return step_fail!("Có destination chưa đạt báo cáo preflight đã chọn.") if @rejected_destination_ids.any?
    return step_fail!("Chọn ít nhất một destination đã đạt preflight.") if @social_destinations.empty?
    return false unless step_validate_destination_consents

    true
  end

  def step_validate_destination_consents
    @social_destinations.each do |social_destination|
      case social_destination.provider
      when "tiktok"
        return false unless step_validate_tiktok_consent(social_destination)
      when "youtube"
        return false unless step_validate_youtube_consent(social_destination)
      end
    end
    true
  end

  def step_validate_tiktok_consent(social_destination)
    consent_snapshot = step_destination_consent_snapshot(social_destination)
    consent_matches_destination = consent_snapshot["tiktok_social_connection_id"].to_s == social_destination.social_connection_id.to_s &&
      consent_snapshot["tiktok_creator_id"].to_s == social_destination.external_id.to_s &&
      consent_snapshot["tiktok_render_version_id"].to_s == @render_version.id.to_s &&
      consent_snapshot["tiktok_publication_id"].present?
    return true if consent_snapshot["tiktok_confirmed_at"].present? && consent_matches_destination

    step_fail!("Cần lưu và xác nhận consent TikTok trước khi lập lịch.")
  end

  def step_validate_youtube_consent(social_destination)
    consent_snapshot = step_destination_consent_snapshot(social_destination)
    consent_matches_destination = consent_snapshot["youtube_account_id"].to_s == social_destination.social_connection.external_user_id.to_s &&
      consent_snapshot["youtube_channel_id"].to_s == social_destination.external_id.to_s &&
      consent_snapshot["render_version_id"].to_s == @render_version.id.to_s &&
      consent_snapshot["publication_id"].present?
    return true if consent_snapshot["upload_terms_confirmed"] == true &&
      consent_snapshot["privacy_status"].present? && consent_matches_destination

    step_fail!("Cần lưu thông tin tải YouTube trước khi lập lịch.")
  end

  def step_destination_consent_snapshot(social_destination)
    @destination_settings.fetch(social_destination.id.to_s).fetch("consent_snapshot", {}).to_h.stringify_keys
  end

  def step_load_schedule_time
    return step_fail!("Loại lịch không được hỗ trợ.") unless Schedule.recurrences.key?(@recurrence_input)

    @time_zone = step_resolve_time_zone
    return step_fail!("Timezone đã chọn không hợp lệ.") unless @time_zone

    zone = ActiveSupport::TimeZone[@time_zone]
    @scheduled_at = if @scheduled_at_input.respond_to?(:in_time_zone)
      @scheduled_at_input.in_time_zone(zone)
    else
      zone.parse(@scheduled_at_input.to_s)
    end
    return step_fail!("Thời gian lập lịch không hợp lệ.") unless @scheduled_at
    return step_fail!("Thời gian lập lịch phải nằm trong tương lai.") unless @scheduled_at > Time.current

    true
  rescue ArgumentError, TypeError
    step_fail!("Thời gian lập lịch không hợp lệ.")
  end

  def step_resolve_time_zone
    return ActiveSupport::TimeZone[@time_zone_input]&.name if @time_zone_input.present?

    service = Schedules::MachineTimeZoneService.new
    service.call ? service.time_zone : nil
  end

  def step_create_schedule
    Schedule.transaction do
      @schedule = @render_version.schedules.create!(
        recurrence: @recurrence_input,
        time_zone: @time_zone,
        local_time: @scheduled_at.in_time_zone(@time_zone).strftime("%H:%M:%S"),
        next_occurrence_at: @scheduled_at
      )
      step_create_schedule_destinations
      @occurrence = @schedule.schedule_occurrences.create!(
        occurrence_key: step_occurrence_key(@scheduled_at),
        scheduled_at: @scheduled_at,
        dispatch_at: @scheduled_at + step_jitter_seconds.seconds
      )
    end
  end

  def step_enqueue_sheet_syncs
    SheetSyncs::EnqueueForScheduleService.new(schedule_id: schedule.id).call
  end

  def step_enqueue_drive_exports
    GoogleConnection.where(integration: "drive", status: :connected).find_each do |google_connection|
      DriveExports::CreateService.new(
        video_project_id: @video_project.id,
        render_version_id: @render_version.id,
        google_connection_id: google_connection.id
      ).call
    end
  end

  def step_create_schedule_destinations
    @social_destinations.each do |social_destination|
      destination_settings = @destination_settings.fetch(social_destination.id.to_s)
      @schedule.schedule_destinations.create!(
        social_destination:,
        caption: destination_settings.fetch("caption", ""),
        consent_snapshot: step_consent_snapshot(social_destination, destination_settings)
      )
    end
  end

  def step_consent_snapshot(social_destination, destination_settings)
    snapshot = destination_settings.fetch("consent_snapshot", {}).to_h.stringify_keys
    return snapshot unless social_destination.provider == "tiktok"

    snapshot.merge("tiktok_schedule_id" => @schedule.id)
  end

  def step_occurrence_key(scheduled_at)
    scheduled_at.utc.iso8601(6)
  end

  def step_jitter_seconds
    minimum = CONFIGURATION.fetch(:jitter_min_seconds).to_i
    maximum = CONFIGURATION.fetch(:jitter_max_seconds).to_i
    minimum + SecureRandom.random_number(maximum - minimum + 1)
  end
end
