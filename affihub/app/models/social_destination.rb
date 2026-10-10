class SocialDestination < ApplicationRecord
  CONFIGURATION = Rails.application.config_for(:meta).deep_symbolize_keys
  STATUS_CONFIGURATION = CONFIGURATION.fetch(:statuses).fetch(:social_destination)
  PROVIDERS = CONFIGURATION.fetch(:providers).keys.map(&:to_s).freeze
  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  encrypts :access_token

  belongs_to :social_connection, inverse_of: :social_destinations
  has_many :publications, inverse_of: :social_destination, dependent: :restrict_with_exception
  has_many :sheet_syncs, inverse_of: :social_destination, dependent: :restrict_with_exception
  has_many :publication_quota_reservations, inverse_of: :social_destination, dependent: :restrict_with_exception
  has_many :schedule_destinations, inverse_of: :social_destination, dependent: :restrict_with_exception
  has_many :auto_reply_rules, inverse_of: :social_destination, dependent: :destroy
  has_many :auto_reply_events, inverse_of: :social_destination, dependent: :restrict_with_exception

  validates :provider, :external_id, :name, :access_token, presence: true
  validates :provider, inclusion: { in: PROVIDERS }
  validates :external_id, uniqueness: { scope: :social_connection_id }
  validate :provider_matches_social_connection

  # Reports whether Meta granted a Page task that allows content creation.
  #
  # @param tasks [Array<String>] tasks returned with a Meta Page
  # @param provider [String, Symbol] the provider whose Page permissions apply
  # @return [Boolean] whether one configured task allows content creation
  def self.can_create_content?(tasks, provider: :facebook)
    allowed_tasks = SocialConnections::ProviderConfiguration.for(provider).fetch(:page_create_content_tasks, [])
    (Array(tasks) & allowed_tasks).any?
  end

  private

  def provider_matches_social_connection
    return if social_connection.blank? || provider == social_connection.provider

    errors.add(:provider, :invalid)
  end
end
