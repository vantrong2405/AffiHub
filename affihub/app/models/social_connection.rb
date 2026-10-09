class SocialConnection < ApplicationRecord
  CONFIGURATION = Rails.application.config_for(:meta).deep_symbolize_keys
  STATUS_CONFIGURATION = CONFIGURATION.fetch(:statuses).fetch(:social_connection)
  PROVIDERS = CONFIGURATION.fetch(:providers).keys.map(&:to_s).freeze

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  encrypts :access_token, :refresh_token

  has_many :social_destinations, inverse_of: :social_connection, dependent: :restrict_with_exception

  validates :provider, :external_user_id, :name, :access_token, presence: true
  validates :provider, inclusion: { in: PROVIDERS }
  validates :external_user_id, uniqueness: { scope: :provider }

  scope :with_publish_attempt_since, proc { |provider:, operation:, stage:, since:|
    joins(social_destinations: { publications: { workflow_runs: :outbound_attempts } })
      .where(
        provider:,
        social_destinations: { provider: },
        workflow_runs: { operation:, stage: },
        outbound_attempts: { stage:, request_started_at: since..Time.current }
      )
      .distinct
  }
end
