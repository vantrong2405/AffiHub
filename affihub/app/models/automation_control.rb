class AutomationControl < ApplicationRecord
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:auto_responder)

  attribute :auto_responder_paused, :boolean, default: CONFIGURATION.fetch(:paused_by_default)

  validates :scope_key, presence: true, uniqueness: true

  # Loads or creates the one persisted global automation-control record.
  #
  # @return [AutomationControl] the global automation-control record
  def self.current
    create_or_find_by!(scope_key: CONFIGURATION.fetch(:control_scope_key))
  end
end
