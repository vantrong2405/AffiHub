class AiGeneration < ApplicationRecord
  STATUS_CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:ai_generation)

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  belongs_to :video_project, inverse_of: :ai_generations
  belongs_to :source_asset, inverse_of: :ai_generations, optional: true
  has_one :workflow_run, as: :workflowable, inverse_of: :workflowable, dependent: :restrict_with_exception
  has_many :ai_generation_scenes, inverse_of: :ai_generation, dependent: :destroy

  has_many_attached :clips
  has_one_attached :voiceover
  has_one_attached :subtitle
  has_one_attached :preview_video

  validates :correlation_id, presence: true, uniqueness: true
  validates :task_id, uniqueness: true, allow_nil: true

  validate :source_asset_belongs_to_video_project

  private

  def source_asset_belongs_to_video_project
    return if source_asset.blank? || source_asset.video_project_id == video_project_id

    errors.add(:source_asset, :invalid)
  end
end
