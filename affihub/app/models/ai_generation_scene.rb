class AiGenerationScene < ApplicationRecord
  STATUS_CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:ai_generation_scene)

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  belongs_to :ai_generation, inverse_of: :ai_generation_scenes
  has_one :workflow_run, as: :workflowable, inverse_of: :workflowable, dependent: :restrict_with_exception
  has_one_attached :voiceover

  # Returns scenes in stable scene-index order.
  #
  # @return [ActiveRecord::Relation<AiGenerationScene>] the ordered scenes
  scope :in_order, proc { order(:scene_index, :id) }

  validates :scene_index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :scene_index, uniqueness: { scope: :ai_generation_id }
  validates :narration_snapshot, :voice_name, presence: true
end
