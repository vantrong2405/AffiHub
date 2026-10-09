# frozen_string_literal: true

class PreflightReports::ShowService < ApplicationService
  attr_reader :preflight_report, :video_project, :render_version, :frame_strip, :frame_error,
    :project_checks, :destination_entries, :displayed_destination_entries, :selected_destination_id

  # Initializes the report review and frame comparison for one persisted audit.
  #
  # @param video_project_id [Integer] the project that owns the report
  # @param preflight_report_id [Integer] the report being reviewed
  # @param destination_id [Integer, String, nil] an optional destination filter
  # @return [PreflightReports::ShowService] the configured service
  def initialize(video_project_id:, preflight_report_id:, destination_id: nil)
    @video_project_id = video_project_id
    @preflight_report_id = preflight_report_id
    @destination_id = destination_id
    @configuration = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:preflight)
    @frame_strip = []
    @destination_entries = []
    @displayed_destination_entries = []
    @project_checks = {}
    super()
  end

  # Loads the saved report and extracts paired source/render frames at configured intervals.
  #
  # @return [Boolean] whether the report and its comparison frames were loaded
  def call
    return false unless step_load_preflight_report
    return false unless step_build_destination_entries
    return false unless step_select_destination_entries
    return false unless step_build_frame_strip

    step_succeed!
    success?
  end

  private

  def step_load_preflight_report
    @video_project = VideoProject.find(@video_project_id)
    @preflight_report = PreflightReport.joins(:render_version)
      .includes(render_version: :source_asset)
      .where(render_versions: { video_project_id: video_project.id })
      .find(@preflight_report_id)

    @render_version = preflight_report.render_version
    @project_checks = step_order_checks(
      preflight_report.destination_results.dig("project", "checks").to_h,
      @configuration.fetch(:project_check_order)
    )
    true
  end

  def step_build_destination_entries
    destination_ids = preflight_report.checked_destination_ids.map(&:to_i)
    destinations_by_id = SocialDestination.includes(:social_connection).where(id: destination_ids).index_by(&:id)
    results = preflight_report.destination_results.to_h

    @destination_entries = destination_ids.filter_map do |destination_id|
      result = results[destination_id.to_s]
      next unless result

      destination = destinations_by_id[destination_id]
      checks = step_order_checks(result.fetch("checks", {}).to_h, @configuration.fetch(:destination_check_order))
      {
        id: destination_id,
        name: step_destination_subject(checks) || destination&.name || "Destination ##{destination_id}",
        provider: destination&.provider,
        social_connection_id: destination&.social_connection_id,
        status: result.fetch("status", "unavailable"),
        checks:
      }
    end

    true
  end

  def step_select_destination_entries
    @selected_destination_id = @destination_id.presence&.to_s
    return @displayed_destination_entries = destination_entries if selected_destination_id.blank?

    selected_entry = destination_entries.find { |entry| entry.fetch(:id).to_s == selected_destination_id }
    return step_fail!("Destination không nằm trong phạm vi của báo cáo preflight.") unless selected_entry

    @displayed_destination_entries = [ selected_entry ]
  end

  def step_destination_subject(checks)
    checks.dig("connector", "subject") || checks.dig("media_transfer", "subject") || checks.values.first&.fetch("subject", nil)
  end

  def step_order_checks(checks, configured_order)
    checks.sort_by do |key, _value|
      [ configured_order.index(key) || configured_order.length, key ]
    end.to_h
  end

  def step_build_frame_strip
    duration = step_comparison_duration
    unless duration&.positive?
      @frame_error = "Chưa thể xác định thời lượng source và render để tạo khung đối chiếu."
      return true
    end

    comparison_service = RenderVersions::CompareFramesService.new(
      render_version_id: render_version.id,
      timecodes: step_frame_timecodes(duration)
    )
    unless comparison_service.call
      @frame_error = comparison_service.errors.full_messages.to_sentence.presence || "Không thể tạo khung hình so sánh."
      return true
    end

    @frame_strip = comparison_service.frames
    true
  end

  def step_comparison_duration
    source_duration = Float(render_version.source_asset.media_metadata.fetch("duration_seconds"))
    render_duration = Float(render_version.metadata.fetch("duration_seconds"))
    [ source_duration, render_duration ].min
  rescue KeyError, ArgumentError, TypeError
    nil
  end

  def step_frame_timecodes(duration)
    interval = @configuration.fetch(:frame_interval_seconds).to_f
    timecodes = []
    timecode = 0.0
    while timecode < duration
      timecodes << timecode
      timecode += interval
    end
    timecodes
  end
end
