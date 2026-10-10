class SheetSync < ApplicationRecord
  CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys
  STATUS_CONFIGURATION = CONFIGURATION.fetch(:statuses).fetch(:sheet_sync)
  TELEGRAM_ALERT_ERROR_CODES = CONFIGURATION.fetch(:sheets).fetch(:safe_error_codes)
    .values_at(:retry_exhausted, :sync_outcome_unknown).freeze

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  belongs_to :google_connection, inverse_of: :sheet_syncs
  belongs_to :render_version, inverse_of: :sheet_syncs
  belongs_to :social_destination, inverse_of: :sheet_syncs

  validates :sheet_row_key, presence: true
  validates :sheet_row_key, uniqueness: { scope: %i[google_connection_id render_version_id social_destination_id] }

  after_commit :enqueue_telegram_alert_for_retry_exhaustion, on: :update

  private

  def enqueue_telegram_alert_for_retry_exhaustion
    return unless saved_change_to_status?
    return unless failed? || outcome_unknown?
    return unless TELEGRAM_ALERT_ERROR_CODES.include?(safe_error_code)

    Telegram::Alerts::EnqueueService.new(event: :sheet_sync_retries_exhausted, record: self).call
  end
end
