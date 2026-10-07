class VideoProject < ApplicationRecord
  STATUS_CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:video_project)

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  has_many :source_assets, inverse_of: :video_project, dependent: :restrict_with_error
  has_many :ai_generations, inverse_of: :video_project, dependent: :restrict_with_error
  has_many :project_media_assets, inverse_of: :video_project, dependent: :restrict_with_error
  has_many :render_versions, inverse_of: :video_project, dependent: :restrict_with_error

  scope :ordered_by_name, proc { order(:name, :id) }

  validates :name, presence: true
end
