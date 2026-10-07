class Publication < ApplicationRecord
  STATUS_CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:publication)

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  belongs_to :render_version, inverse_of: :publications
  belongs_to :social_destination, inverse_of: :publications
  has_many :workflow_runs, as: :workflowable, inverse_of: :workflowable, dependent: :restrict_with_exception

  scope :for_destination, proc { |social_destination| where(social_destination:) }
  scope :recent_first, proc { order(created_at: :desc, id: :desc) }

  validates :status, presence: true
end
