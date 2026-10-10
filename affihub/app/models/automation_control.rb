class AutomationControl < ApplicationRecord
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:auto_responder)
  SCHEDULE_CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:schedule)
  TELEGRAM_CONFIGURATION = Rails.application.config_for(:telegram).deep_symbolize_keys

  attribute :auto_responder_paused, :boolean, default: CONFIGURATION.fetch(:paused_by_default)
  attribute :auto_publish_paused, :boolean, default: SCHEDULE_CONFIGURATION.fetch(:auto_publish_paused_by_default)
  attribute :telegram_worker_down_alerted, :boolean, default: TELEGRAM_CONFIGURATION.fetch(:worker_down_alerted_by_default)

  validates :scope_key, presence: true, uniqueness: true

  # Loads or creates the one persisted global automation-control record.
  #
  # @return [AutomationControl] the global automation-control record
  def self.current
    scope_key = CONFIGURATION.fetch(:control_scope_key)
    find_by(scope_key:) || create_or_find_by!(scope_key:)
  end
end
