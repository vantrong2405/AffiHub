class Schedules::NewService < ApplicationService
  attr_reader :video_project, :preflight_reports, :preflight_report, :render_version,
    :ready_social_destinations, :blocked_social_destinations, :time_zone, :time_zone_options,
    :publications_by_destination, :consent_required_destination_ids

  # Initializes the form data for creating a Schedule from a preflight report.
  #
  # @param video_project_id [Integer] the project whose reports are available
  # @param preflight_report_id [Integer, nil] the selected report
  # @return [Schedules::NewService] the configured service
  def initialize(video_project_id:, preflight_report_id: nil)
    @video_project_id = video_project_id
    @preflight_report_id = preflight_report_id
    super()
  end

  # Loads report, destinations, saved consent and the machine timezone default.
  #
  # @return [Boolean] whether the Schedule form data was loaded
  def call
    return false unless step_load_publication_form_data
    return false unless step_load_time_zone

    step_load_publications
    step_find_missing_consent
    step_succeed!
    success?
  end

  private

  def step_load_publication_form_data
    service = Publications::NewService.new(
      video_project_id: @video_project_id,
      preflight_report_id: @preflight_report_id
    )
    return step_fail!(service.errors.full_messages.to_sentence) unless service.call

    @video_project = service.video_project
    @preflight_reports = service.preflight_reports
    @preflight_report = service.preflight_report
    @render_version = service.render_version
    @ready_social_destinations = service.ready_social_destinations
    @blocked_social_destinations = service.blocked_social_destinations
    true
  end

  def step_load_time_zone
    service = Schedules::MachineTimeZoneService.new
    return step_fail!(service.errors.full_messages.to_sentence) unless service.call

    @time_zone = service.time_zone
    @time_zone_options = (TZInfo::Timezone.all_identifiers + [ "UTC" ]).uniq.sort
    true
  end

  def step_load_publications
    return @publications_by_destination = {} unless render_version

    @publications_by_destination = render_version.publications
      .includes(:social_destination)
      .recent_first
      .each_with_object({}) do |publication, publications_by_destination|
        publications_by_destination[publication.social_destination_id.to_s] ||= publication
      end
  end

  def step_find_missing_consent
    @consent_required_destination_ids = ready_social_destinations.filter_map do |social_destination|
      publication = publications_by_destination[social_destination.id.to_s]
      social_destination.id if step_requires_saved_consent?(social_destination, publication)
    end
  end

  def step_requires_saved_consent?(social_destination, publication)
    return false unless %w[tiktok youtube].include?(social_destination.provider)

    !step_saved_consent_matches?(social_destination, publication)
  end

  def step_saved_consent_matches?(social_destination, publication)
    return false unless publication

    snapshot = publication.consent_snapshot.to_h.stringify_keys
    return step_tiktok_consent_matches?(social_destination, publication, snapshot) if social_destination.provider == "tiktok"
    return step_youtube_consent_matches?(publication, snapshot) if social_destination.provider == "youtube"

    true
  end

  def step_tiktok_consent_matches?(social_destination, publication, snapshot)
    snapshot["tiktok_confirmed_at"].present? &&
      snapshot["tiktok_social_connection_id"].to_s == social_destination.social_connection_id.to_s &&
      snapshot["tiktok_creator_id"].to_s == social_destination.external_id.to_s &&
      snapshot["tiktok_render_version_id"].to_s == publication.render_version_id.to_s &&
      snapshot["tiktok_publication_id"].to_s == publication.id.to_s
  end

  def step_youtube_consent_matches?(publication, snapshot)
    snapshot["upload_terms_confirmed"] == true &&
      snapshot["privacy_status"].present? &&
      snapshot["render_version_id"].to_s == publication.render_version_id.to_s &&
      snapshot["publication_id"].to_s == publication.id.to_s
  end
end
