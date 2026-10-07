class RenderVersions::CreateService < ApplicationService
  attr_reader :render_version

  # Initializes a new immutable render version for one ready source.
  #
  # @param video_project [VideoProject] the project that owns the source
  # @param source_asset [SourceAsset] the ready source selected for rendering
  # @param edit_config [Hash] schema version 1 timeline and overlay configuration
  # @return [RenderVersions::CreateService] the configured service
  def initialize(video_project:, source_asset:, edit_config:)
    @video_project = video_project
    @source_asset = source_asset
    @edit_config = edit_config
    super()
  end

  # Validates, persists, and queues a new immutable render version.
  #
  # @return [Boolean] whether the version was created and queued
  def call
    return false unless step_validate_edit_config
    return false unless step_create_version

    RenderVersions::RenderJob.perform_later(render_version.id)
    step_succeed!
    success?
  end

  private

  def step_validate_edit_config
    validator = RenderVersions::EditConfigValidator.new(
      video_project: @video_project,
      source_asset: @source_asset,
      edit_config: @edit_config
    )
    return true if validator.call

    step_fail!(validator.errors.full_messages.to_sentence)
  end

  def step_create_version
    failure_message = nil

    @source_asset.with_lock do
      unless @source_asset.ready? && @source_asset.video_project_id == @video_project.id
        failure_message = "Chỉ có thể tạo render từ video sẵn sàng trong project hiện tại."
        next
      end

      next_version_number = @source_asset.render_versions.maximum(:version_number).to_i + 1
      @render_version = @video_project.render_versions.build(
        source_asset: @source_asset,
        version_number: next_version_number,
        edit_config: @edit_config
      )
      failure_message = @render_version.errors.full_messages.to_sentence unless @render_version.save
    end

    return step_fail!(failure_message) if failure_message.present?

    true
  rescue ActiveRecord::RecordNotUnique
    step_fail!("Không thể cấp số phiên bản render. Hãy thử lại.")
  end
end
