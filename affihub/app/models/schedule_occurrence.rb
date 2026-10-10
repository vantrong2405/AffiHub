class ScheduleOccurrence < ApplicationRecord
  SCHEDULE_CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:schedule)
  STATUS_CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:schedule_occurrence)

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  belongs_to :schedule, inverse_of: :schedule_occurrences
  belongs_to :preflight_report, optional: true, inverse_of: :schedule_occurrences
  has_many :publications, inverse_of: :schedule_occurrence, dependent: :restrict_with_exception

  validates :occurrence_key, :scheduled_at, :dispatch_at, presence: true
  validates :occurrence_key, uniqueness: { scope: :schedule_id }
  validate :dispatch_time_is_within_jitter_window

  private

  def dispatch_time_is_within_jitter_window
    return if scheduled_at.blank? || dispatch_at.blank?

    minimum = scheduled_at + SCHEDULE_CONFIGURATION.fetch(:jitter_min_seconds).to_i.seconds
    maximum = scheduled_at + SCHEDULE_CONFIGURATION.fetch(:jitter_max_seconds).to_i.seconds
    return if dispatch_at.between?(minimum, maximum)

    errors.add(:dispatch_at, :invalid)
  end
end
