require "uri"

class SourceAssets::CreateFromUrlService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:source_download)

  attr_reader :source_asset, :video_project

  # Initializes a user-confirmed URL source import.
  #
  # @param video_project [VideoProject] the project that owns the new source
  # @param url [String] the HTTPS URL provided by the user
  # @param rights_confirmed [Boolean] whether the user accepted the rights warning
  # @return [SourceAssets::CreateFromUrlService] the configured service
  def initialize(video_project:, url:, rights_confirmed:)
    @video_project = video_project
    @url = url.to_s.strip
    @rights_confirmed = ActiveModel::Type::Boolean.new.cast(rights_confirmed)
    super()
  end

  # Persists a validated URL source and enqueues its background download.
  #
  # @return [Boolean] whether the source was saved and queued
  def call
    return false unless step_validate_request
    return false unless step_persist_source

    step_enqueue_download
    step_succeed!
    success?
  end

  private

  def step_validate_request
    return step_fail!("Hãy mở và xác nhận cảnh báo quyền sử dụng trước khi tải.") unless @rights_confirmed
    return step_fail!("Không tìm thấy project để nhập video.") unless video_project&.persisted?
    return step_fail!("Hãy nhập một URL video.") if @url.blank?

    SourceAssets::DownloadEgressProxy.new.validate_url(url: @url)
  rescue SourceAssets::DownloadEgressProxy::BlockedDestination
    step_fail!("Chỉ nhận URL HTTPS từ nguồn đã cấu hình và có địa chỉ mạng công khai.")
  end

  def step_persist_source
    uri = URI.parse(@url)
    @source_asset = video_project.source_assets.build(
      source_type: "url_download",
      source_url: @url,
      provenance: { "platform" => step_platform_for(uri.host), "method" => "url_import" }
    )
    return true if source_asset.save

    step_fail!(source_asset.errors.full_messages.to_sentence)
  end

  def step_enqueue_download
    SourceAssets::DownloadJob.perform_later(source_asset.id)
  end

  def step_platform_for(host)
    normalized_host = host.downcase.delete_suffix(".")
    CONFIGURATION.fetch(:platform_hosts).each do |platform, domains|
      return platform.to_s if domains.any? do |domain|
        normalized_host == domain || normalized_host.end_with?(".#{domain}")
      end
    end

    "external"
  end
end
