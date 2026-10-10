class SheetSyncs::SyncJob < ApplicationJob
  CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys
  SHEETS_CONFIGURATION = CONFIGURATION.fetch(:sheets)
  RETRY_CONFIGURATION = SHEETS_CONFIGURATION.fetch(:rate_limit)

  # Calculates the configured exponential delay for one transient Sheets failure.
  #
  # @param executions [Integer] the number of attempts already made
  # @return [Integer] the retry delay in seconds
  def self.retry_delay(executions)
    initial_wait = RETRY_CONFIGURATION.fetch(:initial_wait_seconds)
    maximum_wait = RETRY_CONFIGURATION.fetch(:maximum_wait_seconds)
    [ initial_wait * (2**(executions - 1)), maximum_wait ].min
  end

  retry_on Google::Client::RateLimitError, Google::Client::NetworkError, Timeout::Error,
    wait: method(:retry_delay).to_proc,
    attempts: RETRY_CONFIGURATION.fetch(:attempts),
    jitter: 0 do |job, error|
      sheet_sync = SheetSync.find_by(id: job.arguments.first)
      next unless sheet_sync

      safe_error_code = if error.is_a?(Google::Client::NetworkError) || error.is_a?(Timeout::Error)
        SHEETS_CONFIGURATION.fetch(:safe_error_codes).fetch(:sync_outcome_unknown)
      else
        SHEETS_CONFIGURATION.fetch(:safe_error_codes).fetch(:retry_exhausted)
      end
      status = safe_error_code == SHEETS_CONFIGURATION.fetch(:safe_error_codes).fetch(:sync_outcome_unknown) ?
        :outcome_unknown : :failed
      sheet_sync.update!(status:, safe_error_code:)
    end

  # Runs one isolated Sheets sync job without invoking a publisher.
  #
  # @param sheet_sync_id [Integer] the persisted sync request
  # @return [Boolean] whether the Sheets upsert completed
  def perform(sheet_sync_id)
    SheetSyncs::SyncService.new(sheet_sync_id:).call
  end
end
