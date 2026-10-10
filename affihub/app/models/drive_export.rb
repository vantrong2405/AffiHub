class DriveExport < ApplicationRecord
  STATUS_CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:drive_export)

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  encrypts :upload_session_uri

  belongs_to :google_connection, inverse_of: :drive_exports
  belongs_to :render_version, inverse_of: :drive_exports
  has_many :workflow_runs, as: :workflowable, inverse_of: :workflowable, dependent: :restrict_with_exception

  validates :folder_key, :file_key, presence: true
  validates :file_key, uniqueness: true
  validates :upload_offset, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
