class SocialDestination < ApplicationRecord
  CONFIGURATION = Rails.application.config_for(:meta).deep_symbolize_keys
  STATUS_CONFIGURATION = CONFIGURATION.fetch(:statuses).fetch(:social_destination)
  PROVIDERS = CONFIGURATION.fetch(:providers).keys.map(&:to_s).freeze

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  encrypts :access_token

  belongs_to :social_connection, inverse_of: :social_destinations

  validates :provider, :external_id, :name, :access_token, presence: true
  validates :provider, inclusion: { in: PROVIDERS }
  validates :external_id, uniqueness: { scope: :social_connection_id }
  validate :provider_matches_social_connection

  private

  def provider_matches_social_connection
    return if social_connection.blank? || provider == social_connection.provider

    errors.add(:provider, :invalid)
  end
end
