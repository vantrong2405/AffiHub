class Schedule < ApplicationRecord
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:schedule)
  STATUS_CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:schedule)

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym
  enum :recurrence, CONFIGURATION.fetch(:recurrence_values).index_with(&:itself).transform_keys(&:to_sym),
    default: :once, validate: true

  belongs_to :render_version, inverse_of: :schedules
  has_many :schedule_destinations, inverse_of: :schedule, dependent: :restrict_with_exception
  has_many :schedule_occurrences, inverse_of: :schedule, dependent: :restrict_with_exception

  validates :time_zone, :local_time, presence: true
  validates :next_occurrence_at, presence: true, if: :active?
  validate :time_zone_is_supported

  private

  def time_zone_is_supported
    return if time_zone.blank? || ActiveSupport::TimeZone[time_zone]

    errors.add(:time_zone, :invalid)
  end
end
