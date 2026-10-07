class SourceAsset < ApplicationRecord
  STATUS_CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:source_asset)

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  belongs_to :video_project, inverse_of: :source_assets
  has_many :ai_generations, inverse_of: :source_asset, dependent: :restrict_with_error
  has_many :render_versions, inverse_of: :source_asset
  has_one_attached :file

  scope :recent_first, proc { order(created_at: :desc, id: :desc) }
end
