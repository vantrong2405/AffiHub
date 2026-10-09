class SheetSync < ApplicationRecord
  CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys
  STATUS_CONFIGURATION = CONFIGURATION.fetch(:statuses).fetch(:sheet_sync)

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  belongs_to :google_connection, inverse_of: :sheet_syncs
  belongs_to :render_version, inverse_of: :sheet_syncs
  belongs_to :social_destination, inverse_of: :sheet_syncs

  validates :sheet_row_key, presence: true
  validates :sheet_row_key, uniqueness: { scope: %i[google_connection_id render_version_id social_destination_id] }
end
