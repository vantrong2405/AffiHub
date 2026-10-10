class AutoReplyEvent < ApplicationRecord
  STATUS_CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:auto_reply_event)

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  belongs_to :social_destination, inverse_of: :auto_reply_events
  has_many :workflow_runs, as: :workflowable, inverse_of: :workflowable, dependent: :restrict_with_exception

  validates :source, :event_type, :provider_comment_id, :comment_text, presence: true
  validates :provider_comment_id, uniqueness: { scope: :social_destination_id }
end
