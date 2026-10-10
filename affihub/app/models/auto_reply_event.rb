class AutoReplyEvent < ApplicationRecord
  STATUS_CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:auto_reply_event)

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  belongs_to :social_destination, inverse_of: :auto_reply_events
  has_many :workflow_runs, as: :workflowable, inverse_of: :workflowable, dependent: :restrict_with_exception

  after_commit :enqueue_telegram_alert_for_status_change, on: :update

  validates :source, :event_type, :provider_comment_id, :comment_text, presence: true
  validates :provider_comment_id, uniqueness: { scope: :social_destination_id }

  private

  def enqueue_telegram_alert_for_status_change
    return unless saved_change_to_status?

    event = if outcome_unknown?
      :auto_reply_outcome_unknown
    elsif failed?
      :auto_reply_failed
    end
    return unless event

    Telegram::Alerts::EnqueueService.new(event:, record: self).call
  end
end
