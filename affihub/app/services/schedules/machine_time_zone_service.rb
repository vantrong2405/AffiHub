class Schedules::MachineTimeZoneService < ApplicationService
  attr_reader :time_zone

  # Initializes a lookup for the host's local IANA timezone.
  #
  # @return [Schedules::MachineTimeZoneService] the configured service
  def initialize
    super()
  end

  # Returns the host timezone using its configured local timezone data.
  #
  # @return [Boolean] whether a supported timezone was resolved
  def call
    @time_zone = ActiveSupport::TimeZone[step_machine_time_zone_name]&.name || "UTC"
    step_succeed!
    success?
  end

  private

  def step_machine_time_zone_name
    configured_time_zone = ENV["TZ"].presence
    return configured_time_zone if configured_time_zone

    local_time_zone_path = File.realpath("/etc/localtime")
    zoneinfo_marker = "/zoneinfo/"
    marker_position = local_time_zone_path.rindex(zoneinfo_marker)
    return local_time_zone_path[(marker_position + zoneinfo_marker.length)..] if marker_position

    ActiveSupport::TimeZone[Time.now.getlocal.utc_offset]&.name || "UTC"
  rescue Errno::ENOENT
    ActiveSupport::TimeZone[Time.now.getlocal.utc_offset]&.name || "UTC"
  end
end
