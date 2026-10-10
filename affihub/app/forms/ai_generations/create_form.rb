# frozen_string_literal: true

class AiGenerations::CreateForm < MainForm
  PROFILE_CONFIGURATION = Rails.application.config_for(:money_printer_turbo)
    .deep_symbolize_keys
    .fetch(:generation_profile)

  attribute :topic, :string
  attribute :language, :string
  attribute :tone, :string
  attribute :target_duration, :integer
  attribute :ai_provider_connection_id, :integer
  attribute :model_id, :string, default: PROFILE_CONFIGURATION.fetch(:model_id)
  attribute :resolution, :string, default: PROFILE_CONFIGURATION.fetch(:resolution)
  attribute :scene_count, :integer, default: PROFILE_CONFIGURATION.fetch(:scene_count)
  attribute :scene_duration, :integer, default: PROFILE_CONFIGURATION.fetch(:scene_duration)

  validates :topic, :language, :tone, :target_duration, presence: true
  validates :ai_provider_connection_id, presence: { message: "cần chọn tài khoản AI." }
  validates :target_duration, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :scene_count, numericality: { only_integer: true, greater_than: 0 }
  validates :scene_duration,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: PROFILE_CONFIGURATION.fetch(:min_scene_duration),
      less_than_or_equal_to: PROFILE_CONFIGURATION.fetch(:max_scene_duration)
    }
end
