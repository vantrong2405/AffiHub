class Telegram::Workers::MonitorService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:telegram).deep_symbolize_keys
  STATUS_CONFIGURATION = CONFIGURATION.fetch(:statuses).fetch(:worker_status)

  # Initializes a worker monitor with its heartbeat status reader.
  #
  # @param worker_status_service [Telegram::Workers::StatusService] the Solid Queue heartbeat reader
  # @return [Telegram::Workers::MonitorService] the configured monitor service
  def initialize(worker_status_service: Telegram::Workers::StatusService.new)
    @worker_status_service = worker_status_service
    super()
  end

  # Enqueues one alert on a worker-down transition and clears it after recovery.
  #
  # @return [Boolean] whether the worker state was handled
  def call
    worker_status = @worker_status_service.call
    return false if worker_status == STATUS_CONFIGURATION.fetch(:unavailable).to_sym
    return false unless [ STATUS_CONFIGURATION.fetch(:running).to_sym,
      STATUS_CONFIGURATION.fetch(:stopped).to_sym ].member?(worker_status)

    @automation_control = AutomationControl.current
    return step_clear_down_alert if worker_status == STATUS_CONFIGURATION.fetch(:running).to_sym
    return true if @automation_control.telegram_worker_down_alerted?
    return false unless step_enqueue_worker_down_alert

    @automation_control.update!(telegram_worker_down_alerted: true)
    step_succeed!
    success?
  rescue StandardError
    Rails.logger.error("Telegram worker monitor failed.")
    false
  end

  private

  def step_enqueue_worker_down_alert
    Telegram::Alerts::EnqueueService.new(event: :worker_down).call
  end

  def step_clear_down_alert
    @automation_control.update!(telegram_worker_down_alerted: false) if @automation_control.telegram_worker_down_alerted?
    step_succeed!
    success?
  end
end
