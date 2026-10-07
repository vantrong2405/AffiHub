class RenderVersion < ApplicationRecord
  STATUS_CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:render_version)

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  belongs_to :video_project, inverse_of: :render_versions
  belongs_to :source_asset, inverse_of: :render_versions
  has_one_attached :file
  has_many :preflight_reports, inverse_of: :render_version, dependent: :restrict_with_exception
  has_many :publications, inverse_of: :render_version, dependent: :restrict_with_exception

  scope :recent_first, proc { order(created_at: :desc, id: :desc) }

  validate :source_asset_is_ready_for_project
  validate :render_configuration_is_immutable, on: :update
  validate :ready_render_is_immutable, on: :update

  private

  def render_configuration_is_immutable
    return unless will_save_change_to_video_project_id? ||
      will_save_change_to_source_asset_id? ||
      will_save_change_to_version_number? ||
      will_save_change_to_edit_config?

    errors.add(:base, "Cấu hình render không thể thay đổi sau khi tạo.")
  end

  def ready_render_is_immutable
    return unless status_in_database == "ready"
    return unless will_save_change_to_status? || will_save_change_to_metadata? || will_save_change_to_render_error?

    errors.add(:base, "Bản render đã sẵn sàng và không thể thay đổi.")
  end

  def source_asset_is_ready_for_project
    return if source_asset.blank? || video_project.blank?
    return if source_asset.ready? && source_asset.video_project == video_project

    errors.add(:source_asset, :invalid)
  end
end
