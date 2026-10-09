class Schedules::SchedulerJob < ApplicationJob
  queue_as :default

  # Runs a persisted Scheduler scan outside the request-response cycle.
  #
  # @return [Boolean] whether due schedules and queued workflows were processed
  def perform
    Schedules::SchedulerService.new.call
  end
end
