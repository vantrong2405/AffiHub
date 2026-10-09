module SchedulesHelper
  SCHEDULE_RECURRENCE_OPTIONS = [
    [ "Một lần", "once" ],
    [ "Hằng ngày", "daily" ],
    [ "Hằng tuần", "weekly" ]
  ].freeze

  SCHEDULE_STATUS_LABELS = {
    "active" => [ "Đang hoạt động", "badge-success" ],
    "paused" => [ "Đã tạm dừng", "badge-warning" ],
    "completed" => [ "Đã hoàn tất", "badge-neutral" ],
    "cancelled" => [ "Đã hủy", "badge-neutral" ]
  }.freeze

  OCCURRENCE_STATUS_LABELS = {
    "scheduled" => [ "Sắp tới", "badge-info" ],
    "dispatched" => [ "Đã chuyển cho worker", "badge-info" ],
    "missed" => [ "Bị lỡ", "badge-error" ],
    "skipped" => [ "Đã bỏ qua", "badge-warning" ],
    "failed" => [ "Cần kiểm tra", "badge-error" ]
  }.freeze

  PUBLICATION_STATUS_LABELS = {
    "draft" => [ "Bản nháp", "badge-warning" ],
    "approved" => [ "Đã duyệt", "badge-info" ],
    "scheduled" => [ "Đã lên lịch", "badge-info" ],
    "uploading" => [ "Đang tải lên", "badge-info" ],
    "processing" => [ "Đang xử lý", "badge-info" ],
    "published" => [ "Đã đăng", "badge-success" ],
    "failed" => [ "Thất bại", "badge-error" ],
    "outcome_unknown" => [ "Chưa xác định", "badge-error" ],
    "manual_outcome_confirmed" => [ "Đã xác nhận thủ công", "badge-success" ],
    "manual_outcome_not_occurred" => [ "Đã xác nhận chưa đăng", "badge-warning" ]
  }.freeze

  # Renders a Vietnamese badge for a Schedule's persisted state.
  #
  # @param schedule [Schedule] the Schedule whose state is displayed
  # @return [ActiveSupport::SafeBuffer] the status badge
  def schedule_status_badge(schedule)
    label, badge_class = SCHEDULE_STATUS_LABELS.fetch(schedule.status)
    content_tag(:span, label, class: [ "badge", badge_class ])
  end

  # Renders a Vietnamese badge for one Schedule occurrence.
  #
  # @param occurrence [ScheduleOccurrence] the occurrence whose state is displayed
  # @return [ActiveSupport::SafeBuffer] the status badge
  def schedule_occurrence_status_badge(occurrence)
    label, badge_class = OCCURRENCE_STATUS_LABELS.fetch(occurrence.status)
    content_tag(:span, label, class: [ "badge", badge_class ])
  end

  # Returns the Vietnamese label for a Schedule recurrence.
  #
  # @param schedule [Schedule] the Schedule whose recurrence is displayed
  # @return [String] the recurrence label
  def schedule_recurrence_label(schedule)
    {
      "once" => "Một lần",
      "daily" => "Hằng ngày",
      "weekly" => "Hằng tuần"
    }.fetch(schedule.recurrence)
  end

  # Renders a Vietnamese badge for a Publication attached to an occurrence.
  #
  # @param publication [Publication] the Publication whose state is displayed
  # @return [ActiveSupport::SafeBuffer] the status badge
  def schedule_publication_status_badge(publication)
    label, badge_class = PUBLICATION_STATUS_LABELS.fetch(publication.status)
    content_tag(:span, label, class: [ "badge", badge_class ])
  end

  # Builds the report choices for the Schedule creation form.
  #
  # @param preflight_reports [Enumerable<PreflightReport>] reports available to this project
  # @return [Array<Array(String, Integer)>] label and report ID pairs
  def schedule_preflight_report_options(preflight_reports)
    report_options = preflight_reports.map do |preflight_report|
      label = "Version #{preflight_report.render_version.version_number} · #{l(preflight_report.checked_at, format: :short)}"
      [ label, preflight_report.id ]
    end

    [ [ "Chọn báo cáo", "" ] ] + report_options
  end

  # Returns the selected preflight report ID for the Schedule form.
  #
  # @param preflight_report [PreflightReport, nil] selected report
  # @return [Integer, nil] report ID or nil when no report is selected
  def schedule_selected_preflight_report_id(preflight_report)
    preflight_report&.id
  end

  # Reports whether the project has any preflight reports to schedule.
  #
  # @param preflight_reports [Enumerable<PreflightReport>] reports available to this project
  # @return [Boolean] whether at least one report is available
  def schedule_preflight_reports_empty?(preflight_reports)
    preflight_reports.empty?
  end

  # Reports whether a preflight report has been selected for the Schedule form.
  #
  # @param preflight_report [PreflightReport, nil] selected report
  # @return [Boolean] whether a report is selected
  def schedule_preflight_report_selected?(preflight_report)
    preflight_report.present?
  end

  # Reports whether a Schedule form is editing an existing Schedule.
  #
  # @param schedule [Schedule, nil] Schedule supplied to the form
  # @return [Boolean] whether the form is editing a persisted Schedule
  def schedule_form_editing?(schedule)
    schedule.present?
  end

  # Formats the selected preflight report check time for display.
  #
  # @param preflight_report [PreflightReport] selected report
  # @return [String] localized check time
  def schedule_preflight_checked_at(preflight_report)
    l(preflight_report.checked_at, format: :long)
  end

  # Reports whether a destination collection has entries to render.
  #
  # @param social_destinations [Enumerable<SocialDestination>] destinations prepared for the form
  # @return [Boolean] whether at least one destination is available
  def schedule_destinations_present?(social_destinations)
    social_destinations.present?
  end

  # Reports whether a Schedule collection has rows to render.
  #
  # @param schedules [Enumerable<Schedule>] schedules prepared for the index
  # @return [Boolean] whether at least one Schedule is available
  def schedules_present?(schedules)
    schedules.any?
  end

  # Reports whether a Schedule has a next occurrence to display.
  #
  # @param schedule [Schedule] Schedule being displayed
  # @return [Boolean] whether a next occurrence exists
  def schedule_next_occurrence_available?(schedule)
    schedule.next_occurrence_at.present?
  end

  # Reports whether quota summary rows are available to render.
  #
  # @param quota_summary [Enumerable<Hash>] quota rows prepared for the Schedule
  # @return [Boolean] whether at least one quota row exists
  def schedule_quota_summary_present?(quota_summary)
    quota_summary.any?
  end

  # Renders the quota release notice when a destination has a future available slot.
  #
  # @param quota_entry [Hash] quota summary for a destination
  # @param schedule [Schedule] Schedule whose timezone is displayed
  # @return [ActiveSupport::SafeBuffer, nil] localized notice or nil when quota is available
  def schedule_quota_release_notice_element(quota_entry, schedule)
    release_time = schedule_quota_release_time(quota_entry, schedule)
    return unless release_time

    content_tag(:span, "Mở lượt kế tiếp: #{release_time}", class: [ "text-sm", "text-warning" ])
  end

  # Reports whether occurrence rows are available to render.
  #
  # @param occurrences [Enumerable<ScheduleOccurrence>] occurrences prepared for the Schedule
  # @return [Boolean] whether at least one occurrence exists
  def schedule_occurrences_present?(occurrences)
    occurrences.any?
  end

  # Reports whether an occurrence has publications to render.
  #
  # @param occurrence [ScheduleOccurrence] occurrence being displayed
  # @return [Boolean] whether at least one publication exists
  def schedule_occurrence_publications_present?(occurrence)
    occurrence.publications.any?
  end

  # Returns the submit progress label for creating or updating a Schedule.
  #
  # @param schedule [Schedule, nil] Schedule being updated, or nil when creating
  # @return [String] localized submit progress label
  def schedule_submit_progress_label(schedule)
    schedule.present? ? "Đang lưu…" : "Đang tạo lịch…"
  end

  # Builds the timezone choices for the Schedule form.
  #
  # @param time_zone_options [Array<String>, nil] timezone identifiers supplied by the form service
  # @return [Array<Array(String, String)>] timezone label and value pairs
  def schedule_time_zone_select_options(time_zone_options)
    zone_names = time_zone_options.presence || (TZInfo::Timezone.all_identifiers + [ "UTC" ]).uniq.sort
    zone_names.map { |zone_name| [ zone_name, zone_name ] }
  end

  # Returns the recurrence choices for the Schedule form.
  #
  # @return [Array<Array(String, String)>] recurrence label and value pairs
  def schedule_recurrence_select_options
    SCHEDULE_RECURRENCE_OPTIONS
  end

  # Returns the timezone currently selected in the Schedule form.
  #
  # @param schedule_form [Schedules::CreateForm] submitted form state
  # @param schedule [Schedule, nil] Schedule being edited
  # @param default_time_zone [String] machine timezone used for new schedules
  # @return [String] selected timezone identifier
  def schedule_form_time_zone(schedule_form:, schedule:, default_time_zone:)
    schedule_form.time_zone.presence || schedule&.time_zone || default_time_zone
  end

  # Returns the recurrence currently selected in the Schedule form.
  #
  # @param schedule_form [Schedules::CreateForm] submitted form state
  # @param schedule [Schedule, nil] Schedule being edited
  # @return [String] selected recurrence value
  def schedule_form_recurrence(schedule_form:, schedule:)
    schedule_form.recurrence.presence || schedule&.recurrence || "once"
  end

  # Returns the local datetime value currently selected in the Schedule form.
  #
  # @param schedule_form [Schedules::CreateForm] submitted form state
  # @param schedule [Schedule, nil] Schedule being edited
  # @return [String, nil] datetime-local field value
  def schedule_form_scheduled_at(schedule_form:, schedule:)
    return schedule_form.scheduled_at if schedule_form.scheduled_at.present?
    return unless schedule&.next_occurrence_at

    schedule.next_occurrence_at.in_time_zone(schedule.time_zone).strftime("%Y-%m-%dT%H:%M")
  end

  # Prepares one destination's checkbox, caption, and consent state for the Schedule form.
  #
  # @param social_destination [SocialDestination] destination displayed in the form
  # @param schedule_form [Schedules::CreateForm] submitted form state
  # @param publications_by_destination [Hash{String => Publication}] saved drafts by destination ID
  # @param consent_required_destination_ids [Array<Integer>] destinations missing saved consent
  # @return [Hash] prepared destination form values
  def schedule_destination_form_values(social_destination:, schedule_form:, publications_by_destination:,
                                       consent_required_destination_ids:)
    destination_id = social_destination.id.to_s
    publication = publications_by_destination[destination_id]
    consent_required = consent_required_destination_ids.include?(social_destination.id)
    selected = if schedule_form.destination_ids_submitted?
      schedule_form.destination_ids.include?(destination_id)
    else
      !consent_required
    end

    {
      id: destination_id,
      caption: schedule_form.destination_captions.fetch(destination_id, publication&.caption.to_s),
      consent_required:,
      selected:,
      show_consent_revalidation: !consent_required && %w[tiktok youtube].include?(social_destination.provider)
    }
  end

  # Returns the localized next occurrence time for a Schedule list row.
  #
  # @param schedule [Schedule] Schedule being displayed
  # @return [String] localized time or an empty-state label
  def schedule_next_occurrence_label(schedule)
    return "Không còn lần chạy kế tiếp" unless schedule.next_occurrence_at

    l(schedule.next_occurrence_at.in_time_zone(schedule.time_zone), format: :long)
  end

  # Returns the localized next occurrence time for a Schedule.
  #
  # @param schedule [Schedule] Schedule being displayed
  # @return [String, nil] localized time or nil when no occurrence remains
  def schedule_next_occurrence_time(schedule)
    return unless schedule.next_occurrence_at

    l(schedule.next_occurrence_at.in_time_zone(schedule.time_zone), format: :long)
  end

  # Returns the localized occurrence time in its Schedule timezone.
  #
  # @param occurrence [ScheduleOccurrence] occurrence being displayed
  # @param schedule [Schedule] parent Schedule
  # @return [String] localized occurrence time
  def schedule_occurrence_time(occurrence, schedule)
    l(occurrence.scheduled_at.in_time_zone(schedule.time_zone), format: :long)
  end

  # Returns the localized quota release time for a destination.
  #
  # @param quota_entry [Hash] quota summary for a destination
  # @param schedule [Schedule] Schedule whose timezone is displayed
  # @return [String, nil] localized release time or nil when quota is available
  def schedule_quota_release_time(quota_entry, schedule)
    next_available_at = quota_entry.fetch(:next_available_at)
    return unless next_available_at

    l(next_available_at.in_time_zone(schedule.time_zone), format: :long)
  end

  # Returns the destination associated with a quota summary row.
  #
  # @param quota_entry [Hash] quota summary for a destination
  # @return [SocialDestination] destination whose quota is summarized
  def schedule_quota_destination(quota_entry)
    quota_entry.fetch(:social_destination)
  end

  # Returns the used and allowed publication count for a quota summary row.
  #
  # @param quota_entry [Hash] quota summary for a destination
  # @return [String] localized quota count
  def schedule_quota_usage_label(quota_entry)
    "#{quota_entry.fetch(:used)} / #{quota_entry.fetch(:limit)} lượt đã dùng"
  end

  # Returns the destination names attached to a Schedule.
  #
  # @param schedule [Schedule] Schedule being displayed
  # @return [String] names separated by a middle dot
  def schedule_destination_names(schedule)
    schedule.schedule_destinations.map { |entry| entry.social_destination.name }.join(" · ")
  end

  # Returns the user-facing occurrence note for a missed or skipped occurrence.
  #
  # @param occurrence [ScheduleOccurrence] occurrence being displayed
  # @return [String, nil] note for the occurrence state
  def schedule_occurrence_note(occurrence)
    if occurrence.missed?
      "Lần đăng này đã lỡ giờ. AffiHub không tự đăng bù; hãy sửa lịch sang giờ tương lai hoặc tạo lịch mới."
    elsif occurrence.skipped?
      "Occurrence này được bỏ qua khi lịch tạm dừng hoặc bị hủy."
    end
  end

  # Renders a state note for a missed or skipped occurrence.
  #
  # @param occurrence [ScheduleOccurrence] occurrence being displayed
  # @return [ActiveSupport::SafeBuffer, nil] styled note or nil when no note applies
  def schedule_occurrence_note_element(occurrence)
    note = schedule_occurrence_note(occurrence)
    return unless note

    text_class = occurrence.missed? ? "text-error" : "text-base-content/70"
    content_tag(:p, note, class: [ "text-sm", text_class ])
  end

  # Reports whether a Schedule has controls for editing, pausing, or cancellation.
  #
  # @param schedule [Schedule] Schedule being displayed
  # @return [Boolean] whether its state allows schedule controls
  def schedule_controls_available?(schedule)
    schedule.active? || schedule.paused?
  end

  # Reports whether the Schedule detail should offer the resume action.
  #
  # @param schedule [Schedule] Schedule being displayed
  # @return [Boolean] whether the Schedule is paused
  def schedule_resume_available?(schedule)
    schedule.paused?
  end
end
