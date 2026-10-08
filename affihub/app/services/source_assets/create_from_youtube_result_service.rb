require "uri"

class SourceAssets::CreateFromYoutubeResultService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:youtube).deep_symbolize_keys

  attr_reader :source_asset, :video_project

  # Initializes a user-confirmed import from a recently fetched YouTube result.
  #
  # @param video_project [VideoProject] the project that owns the new source
  # @param discovery_metadata_id [Integer] the selected discovery metadata row
  # @param rights_confirmed [Boolean] whether the user accepted the rights warning
  # @return [SourceAssets::CreateFromYoutubeResultService] the configured service
  def initialize(video_project:, discovery_metadata_id:, rights_confirmed:)
    @video_project = video_project
    @discovery_metadata_id = discovery_metadata_id
    @rights_confirmed = ActiveModel::Type::Boolean.new.cast(rights_confirmed)
    super()
  end

  # Persists the selected YouTube source and enqueues its background download.
  #
  # @return [Boolean] whether the source was saved and queued
  def call
    return false unless step_load_metadata
    return false unless step_validate_request
    return false unless step_persist_source

    step_enqueue_download
    step_succeed!
    success?
  end

  private

  def step_load_metadata
    @discovery_metadata = YoutubeDiscoveryMetadata.find_by(id: @discovery_metadata_id)
    return step_fail!("Không tìm thấy kết quả YouTube đã chọn.") unless @discovery_metadata

    true
  end

  def step_validate_request
    return step_fail!("Hãy mở và xác nhận cảnh báo quyền sử dụng trước khi tải.") unless @rights_confirmed
    return step_fail!("Không tìm thấy project để nhập video.") unless video_project&.persisted?
    return step_fail!("Metadata YouTube đã hết hạn. Hãy tìm lại video.") unless step_metadata_is_fresh?

    SourceAssets::DownloadEgressProxy.new.validate_url(url: step_source_url)
  rescue SourceAssets::DownloadEgressProxy::BlockedDestination
    step_fail!("Không thể xác minh URL của kết quả YouTube.")
  end

  def step_metadata_is_fresh?
    @discovery_metadata.fetched_at > CONFIGURATION.fetch(:metadata_ttl_days).days.ago
  end

  def step_source_url
    "https://www.youtube.com/watch?v=#{URI.encode_www_form_component(@discovery_metadata.video_id)}"
  end

  def step_persist_source
    @source_asset = video_project.source_assets.build(
      source_type: "url_download",
      source_url: step_source_url,
      provenance: {
        "platform" => "youtube",
        "method" => "discovery_selection",
        "video_id" => @discovery_metadata.video_id,
        "discovery_type" => @discovery_metadata.discovery_type
      }
    )
    return true if source_asset.save

    step_fail!(source_asset.errors.full_messages.to_sentence)
  end

  def step_enqueue_download
    SourceAssets::DownloadJob.perform_later(source_asset.id)
  end
end
