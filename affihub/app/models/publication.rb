class Publication < ApplicationRecord
  GOOGLE_CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys
  SHEETS_CONFIGURATION = GOOGLE_CONFIGURATION.fetch(:sheets)
  STATUS_CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:publication)

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  belongs_to :render_version, inverse_of: :publications
  belongs_to :social_destination, inverse_of: :publications
  belongs_to :schedule_occurrence, optional: true, inverse_of: :publications
  has_one :quota_reservation, class_name: "PublicationQuotaReservation", inverse_of: :publication,
    dependent: :restrict_with_exception
  has_many :workflow_runs, as: :workflowable, inverse_of: :workflowable, dependent: :restrict_with_exception

  after_commit :enqueue_sheet_sync_for_current_state, on: %i[create update]

  scope :for_destination, proc { |social_destination| where(social_destination:) }
  scope :recent_first, proc { order(created_at: :desc, id: :desc) }

  validates :status, presence: true

  private

  def enqueue_sheet_sync_for_current_state
    state_changed = saved_change_to_status? || saved_change_to_platform_post_id? ||
      saved_change_to_permalink? || saved_change_to_published_at? || saved_change_to_safe_error_code?
    return unless state_changed
    return unless SHEETS_CONFIGURATION.fetch(:publication_trigger_statuses).include?(status)

    SheetSyncs::EnqueueForPublicationService.new(publication_id: id).call
  end
end
