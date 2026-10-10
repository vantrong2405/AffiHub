class Telegram::Workers::StatusService
  CONFIGURATION = Rails.application.config_for(:telegram).deep_symbolize_keys
  STATUS_CONFIGURATION = CONFIGURATION.fetch(:statuses).fetch(:worker_status)

  # Reads the latest Solid Queue Worker heartbeat without changing queue state.
  #
  # @return [Symbol] the configured running, stopped, or unavailable status
  def call
    SolidQueue::Process.transaction(requires_new: true) do
      heartbeat_since = Time.current - CONFIGURATION.fetch(:worker_heartbeat_timeout_seconds).seconds
      active_worker = SolidQueue::Process.where(kind: CONFIGURATION.fetch(:worker_process_kind))
        .where(last_heartbeat_at: heartbeat_since..Time.current)
        .exists?

      active_worker ? STATUS_CONFIGURATION.fetch(:running).to_sym : STATUS_CONFIGURATION.fetch(:stopped).to_sym
    end
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid
    STATUS_CONFIGURATION.fetch(:unavailable).to_sym
  end
end
