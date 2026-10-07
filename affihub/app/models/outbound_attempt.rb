class OutboundAttempt < ApplicationRecord
  STATUS_CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:outbound_attempt)

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  belongs_to :workflow_run, inverse_of: :outbound_attempts

  has_many :workflow_audit_events, inverse_of: :outbound_attempt, dependent: :restrict_with_exception

  scope :for_stage, proc { |stage| where(stage: stage).order(attempt_number: :desc) }

  validates :attempt_id, :attempt_number, :stage, :request_timeout_at, presence: true
  validates :attempt_id, uniqueness: true
  validates :attempt_number, numericality: { only_integer: true, greater_than: 0 }
end
