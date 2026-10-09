class Publications::ShowService < ApplicationService
  # The project that owns the reviewed Publication.
  # @return [VideoProject]
  attr_reader :video_project

  # The Publication being reviewed.
  # @return [Publication]
  attr_reader :publication

  # The latest preflight report for the immutable render version.
  # @return [PreflightReport, nil]
  attr_reader :latest_preflight_report

  # Whether the latest report allows this destination to publish.
  # @return [Boolean]
  attr_reader :preflight_ready

  # The latest publish workflow for the Publication.
  # @return [WorkflowRun, nil]
  attr_reader :workflow_run

  # The latest outbound request attempt for the current workflow.
  # @return [OutboundAttempt, nil]
  attr_reader :outbound_attempt

  # YouTube privacy choices supported by the current API project configuration.
  # @return [Array<String>, nil]
  attr_reader :youtube_privacy_statuses

  # Privacy choices currently permitted by TikTok creator settings and app review status.
  # @return [Array<String>]
  attr_reader :tiktok_privacy_levels

  # Whether the creator has disabled each TikTok interaction.
  # @return [Hash<String, Boolean>]
  attr_reader :tiktok_disabled_interactions

  # Whether complete TikTok creator publishing settings were loaded successfully.
  # @return [Boolean]
  attr_reader :tiktok_creator_info_available

  # Whether TikTok reported a publishing cap or does not expose a remaining-count value.
  # @return [String, nil]
  attr_reader :tiktok_cap_status

  # Configured TikTok cap status values used to render the matching state.
  # @return [Hash, nil]
  attr_reader :tiktok_cap_status_values

  # Whether branded content can be enabled for the current TikTok privacy choices.
  # @return [Boolean, nil]
  attr_reader :tiktok_brand_content_enabled

  # Initializes review data for one Publication in a project.
  #
  # @param video_project_id [Integer] the project that owns the Publication
  # @param publication_id [Integer] the Publication to review
  # @return [Publications::ShowService] the configured service
  def initialize(video_project_id:, publication_id:)
    @video_project_id = video_project_id
    @publication_id = publication_id
    super()
  end

  # Loads the Publication and current preflight/workflow state.
  #
  # @return [Boolean] whether the review data was loaded
  def call
    return false unless step_load_video_project
    return false unless step_load_publication

    step_load_latest_preflight_report
    step_load_latest_workflow_run
    step_load_latest_outbound_attempt
    step_load_youtube_privacy_statuses
    step_load_tiktok_publish_options
    step_succeed!
    success?
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find(@video_project_id)
    true
  end

  def step_load_publication
    @publication = Publication.where(id: video_project.publications.select(:id))
      .includes(:social_destination, :render_version)
      .find(@publication_id)
    true
  end

  def step_load_latest_preflight_report
    @latest_preflight_report = publication.render_version.preflight_reports.recent_first.first
    @preflight_ready = latest_preflight_report&.ready_for?(
      render_version: publication.render_version,
      social_destination: publication.social_destination
    ) || false
  end

  def step_load_latest_workflow_run
    @workflow_run = publication.workflow_runs.order(created_at: :desc, id: :desc).first
  end

  def step_load_latest_outbound_attempt
    @outbound_attempt = workflow_run&.outbound_attempts&.order(attempt_number: :desc)&.first
  end

  def step_load_youtube_privacy_statuses
    return unless publication.social_destination.provider == "youtube"

    configuration = Rails.application.config_for(:youtube).deep_symbolize_keys.fetch(:publisher)
    @youtube_privacy_statuses = configuration.fetch(:privacy_statuses)
  end

  def step_load_tiktok_publish_options
    @tiktok_creator_info_available = false
    return unless publication.social_destination.provider == "tiktok"

    configuration = SocialConnections::ProviderConfiguration.for(:tiktok)
    fields = configuration.fetch(:creator_info_fields)
    cap_statuses = configuration.fetch(:cap_statuses)
    @tiktok_cap_status_values = cap_statuses
    @tiktok_privacy_levels = []
    @tiktok_brand_content_enabled = configuration.fetch(:content_posting_audited)
    @tiktok_disabled_interactions = {
      "comment" => configuration.fetch(:creator_interactions_disabled_when_unavailable),
      "duet" => configuration.fetch(:creator_interactions_disabled_when_unavailable),
      "stitch" => configuration.fetch(:creator_interactions_disabled_when_unavailable)
    }
    @tiktok_cap_status = cap_statuses.fetch(:unavailable_counter)

    token_service = SocialConnections::TikTok::AccessTokenService.new(
      social_destination_id: publication.social_destination_id
    )
    return unless token_service.call

    response = TikTok::Client.new.creator_info(access_token: token_service.access_token)
    error_code = response.dig("error", "code")
    return step_set_tiktok_cap_status(cap_statuses, configuration, error_code) if tiktok_cap_error?(configuration, error_code)
    return unless tiktok_creator_info_successful?(configuration, error_code)

    data = response.fetch("data", {}).to_h
    return unless tiktok_creator_settings_present?(data, fields)

    @tiktok_creator_info_available = true
    creator_privacy_levels = data.fetch(fields.fetch(:privacy_levels))
    @tiktok_privacy_levels = if configuration.fetch(:content_posting_audited)
      creator_privacy_levels
    else
      creator_privacy_levels.select do |privacy_level|
        configuration.fetch(:unaudited_allowed_privacy_levels).include?(privacy_level)
      end
    end
    @tiktok_brand_content_enabled ||= @tiktok_privacy_levels.any? do |privacy_level|
      !configuration.fetch(:unaudited_allowed_privacy_levels).include?(privacy_level)
    end
    @tiktok_disabled_interactions = {
      "comment" => data[fields.fetch(:comment_disabled)] == true,
      "duet" => data[fields.fetch(:duet_disabled)] == true,
      "stitch" => data[fields.fetch(:stitch_disabled)] == true
    }
  rescue TikTok::Client::Error
    @tiktok_cap_status = cap_statuses.fetch(:unavailable_counter)
  end

  def step_set_tiktok_cap_status(cap_statuses, configuration, error_code)
    provider_cap_errors = configuration.fetch(:provider_cap_errors)
    @tiktok_cap_status = if error_code == provider_cap_errors.fetch(:creator)
      cap_statuses.fetch(:creator)
    else
      cap_statuses.fetch(:app)
    end
  end

  def tiktok_cap_error?(configuration, error_code)
    configuration.fetch(:provider_cap_errors).value?(error_code)
  end

  def tiktok_creator_info_successful?(configuration, error_code)
    error_code.blank? || error_code == configuration.fetch(:successful_response_code)
  end

  def tiktok_creator_settings_present?(data, fields)
    return false unless data[fields.fetch(:privacy_levels)].is_a?(Array)

    %i[comment_disabled duet_disabled stitch_disabled].all? do |field|
      value = data[fields.fetch(field)]
      value == true || value == false
    end
  end
end
