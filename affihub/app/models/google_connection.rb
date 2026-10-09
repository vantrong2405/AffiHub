class GoogleConnection < ApplicationRecord
  CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys
  STATUS_CONFIGURATION = CONFIGURATION.fetch(:statuses).fetch(:google_connection)
  INTEGRATIONS = CONFIGURATION.fetch(:oauth).fetch(:integrations).keys.map(&:to_s).freeze

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  encrypts :access_token, :refresh_token

  has_many :drive_exports, inverse_of: :google_connection, dependent: :restrict_with_exception
  has_many :sheet_syncs, inverse_of: :google_connection, dependent: :restrict_with_exception

  validates :integration, :google_account_id, :email, :access_token, presence: true
  validates :integration, inclusion: { in: INTEGRATIONS }
  validates :google_account_id, uniqueness: { scope: :integration }
end
