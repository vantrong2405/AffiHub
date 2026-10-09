class Publications::UpdateService < ApplicationService
  # The project that owns the updated Publication.
  # @return [VideoProject]
  attr_reader :video_project

  attr_reader :publication

  # Initializes a draft Publication update in a project.
  #
  # @param video_project_id [Integer] the project that owns the Publication
  # @param publication_id [Integer] the draft to update
  # @param caption [String] the destination-specific caption
  # @param consent_attributes [Hash] user selections for provider publishing consent
  # @return [Publications::UpdateService] the configured service
  def initialize(video_project_id:, publication_id:, caption:, consent_attributes: {})
    @video_project_id = video_project_id
    @publication_id = publication_id
    @caption = caption
    @consent_attributes = consent_attributes.to_h.stringify_keys
    super()
  end

  # Updates draft content and provider consent while the Publication remains a draft.
  #
  # @return [Boolean] whether the draft caption was updated
  def call
    return false unless step_update_caption

    step_succeed!
    success?
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  private

  def step_update_caption
    Publication.transaction do
      @video_project = VideoProject.find(@video_project_id)
      @publication = video_project.publications.lock.find(@publication_id)
      return step_fail!("Chỉ được sửa caption khi Publication còn là bản nháp.") unless publication.draft?
      if scheduled_tiktok_publication? && tiktok_consent_submitted?
        return false unless step_load_schedule_destination_for_consent
      end

      attributes = { caption: @caption }
      if youtube_consent_submitted?
        attributes[:consent_snapshot] = step_youtube_consent_snapshot
      elsif tiktok_consent_submitted?
        attributes[:consent_snapshot] = step_tiktok_consent_snapshot
      end
      if publication.update(attributes)
        step_update_schedule_destination_consent(attributes[:consent_snapshot]) if @schedule_destination
        return true
      end

      step_fail!(publication.errors.full_messages.to_sentence)
    end
  end

  def youtube_consent_submitted?
    publication.social_destination.provider == "youtube" && @consent_attributes.present?
  end

  def tiktok_consent_submitted?
    publication.social_destination.provider == "tiktok" && @consent_attributes.present?
  end

  def step_youtube_consent_snapshot
    terms_confirmed = @consent_attributes["upload_terms_confirmed"] == "1"
    {
      "upload_terms_confirmed" => terms_confirmed,
      "youtube_account_id" => publication.social_destination.social_connection.external_user_id,
      "youtube_channel_id" => publication.social_destination.external_id,
      "render_version_id" => publication.render_version_id,
      "publication_id" => publication.id,
      "confirmed_at" => terms_confirmed ? Time.current.iso8601 : nil,
      "privacy_status" => @consent_attributes["privacy_status"].presence,
      "self_declared_made_for_kids" => step_boolean_consent("self_declared_made_for_kids"),
      "contains_synthetic_media" => step_boolean_consent("contains_synthetic_media")
    }
  end

  def step_tiktok_consent_snapshot
    social_destination = publication.social_destination
    configuration = SocialConnections::ProviderConfiguration.for(:tiktok)
    consent_snapshot = {
      "privacy_level" => @consent_attributes["privacy_level"].presence,
      "allow_comment" => step_tiktok_boolean_consent("allow_comment"),
      "allow_duet" => step_tiktok_boolean_consent("allow_duet"),
      "allow_stitch" => step_tiktok_boolean_consent("allow_stitch"),
      "brand_organic_toggle" => step_tiktok_boolean_consent("brand_organic_toggle"),
      "brand_content_toggle" => step_tiktok_boolean_consent("brand_content_toggle"),
      "is_aigc" => step_boolean_consent("is_aigc"),
      "creator_account_private" => step_boolean_consent("creator_account_private"),
      "music_usage_confirmed" => step_boolean_consent("music_usage_confirmed"),
      "tiktok_social_connection_id" => social_destination.social_connection_id,
      "tiktok_creator_id" => social_destination.external_id,
      "tiktok_render_version_id" => publication.render_version_id,
      "tiktok_publication_id" => publication.id
    }
    consent_snapshot["tiktok_schedule_id"] = publication.schedule_occurrence.schedule_id if scheduled_tiktok_publication?
    consent_snapshot["tiktok_confirmed_at"] = step_tiktok_consent_complete?(consent_snapshot, configuration) ? Time.current.iso8601 : nil
    consent_snapshot
  end

  def scheduled_tiktok_publication?
    publication.social_destination.provider == "tiktok" && publication.schedule_occurrence_id.present?
  end

  def step_load_schedule_destination_for_consent
    schedule = publication.schedule_occurrence.schedule
    @schedule_destination = schedule.schedule_destinations.find_by(social_destination_id: publication.social_destination_id)
    return true if @schedule_destination

    step_fail!("Không tìm thấy destination đã lưu trong Schedule để cập nhật consent.")
  end

  def step_update_schedule_destination_consent(publication_consent_snapshot)
    schedule_consent_snapshot = publication_consent_snapshot
      .except("tiktok_render_version_id", "tiktok_publication_id")
      .merge("tiktok_schedule_id" => publication.schedule_occurrence.schedule_id)
    @schedule_destination.update!(consent_snapshot: schedule_consent_snapshot)
  end

  def step_tiktok_boolean_consent(key)
    step_boolean_consent(key) == true
  end

  def step_tiktok_consent_complete?(consent_snapshot, configuration)
    return false if consent_snapshot.fetch("privacy_level").blank?
    return false unless [ true, false ].include?(consent_snapshot.fetch("is_aigc"))
    return false if configuration.fetch(:unaudited_requires_private_account) && consent_snapshot.fetch("creator_account_private") != true
    return false if configuration.fetch(:require_music_usage_confirmation) && consent_snapshot.fetch("music_usage_confirmed") != true

    true
  end

  def step_boolean_consent(key)
    value = @consent_attributes[key]
    return if value.blank?

    ActiveModel::Type::Boolean.new.cast(value)
  end
end
