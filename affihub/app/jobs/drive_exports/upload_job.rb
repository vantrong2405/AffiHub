class DriveExports::UploadJob < ApplicationJob
  CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys
  RETRY_CONFIGURATION = CONFIGURATION.fetch(:rate_limit)
  DRIVE_CONFIGURATION = CONFIGURATION.fetch(:drive)

  # Calculates the bounded exponential delay for a transient Google API error.
  #
  # @param executions [Integer] the number of attempts already made
  # @return [Integer] the retry delay in seconds
  def self.rate_limit_retry_delay(executions)
    initial_wait = RETRY_CONFIGURATION.fetch(:initial_wait_seconds)
    maximum_wait = RETRY_CONFIGURATION.fetch(:maximum_wait_seconds)
    [ initial_wait * (2**(executions - 1)), maximum_wait ].min
  end

  retry_on Google::Client::RateLimitError, Google::Client::NetworkError, Timeout::Error,
    wait: method(:rate_limit_retry_delay).to_proc,
    attempts: RETRY_CONFIGURATION.fetch(:attempts),
    jitter: 0 do |job, _error|
      drive_export = DriveExport.find_by(id: job.arguments.first)
      next unless drive_export

      drive_export.update!(
        status: :failed,
        safe_error_code: DRIVE_CONFIGURATION.fetch(:safe_error_codes).fetch(:retry_exhausted)
      )
      workflow_run = drive_export.workflow_runs.find_by(
        operation: DRIVE_CONFIGURATION.fetch(:workflow_operation),
        stage: DRIVE_CONFIGURATION.fetch(:workflow_stage)
      )
      workflow_run&.with_lock do
        workflow_run.update!(status: :failed, worker_id: nil, lease_expires_at: nil)
        workflow_run.workflow_audit_events.create!(
          event_type: DRIVE_CONFIGURATION.fetch(:audit_events).fetch(:retry_exhausted),
          stage: workflow_run.stage,
          worker_id: DRIVE_CONFIGURATION.fetch(:worker_id_prefix),
          fencing_token: workflow_run.fencing_token,
          details: {
            "safe_error_code" => DRIVE_CONFIGURATION.fetch(:safe_error_codes).fetch(:retry_exhausted)
          }
        )
      end
    end

  # Runs the persisted Drive export outside the web request.
  #
  # @param drive_export_id [Integer] the Drive export to upload
  # @return [Boolean] whether Drive confirmed the file metadata
  def perform(drive_export_id)
    DriveExports::UploadService.new(drive_export_id:).call
  end
end
