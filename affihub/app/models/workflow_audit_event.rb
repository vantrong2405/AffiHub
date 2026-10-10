class WorkflowAuditEvent < ApplicationRecord
  belongs_to :workflow_run, inverse_of: :workflow_audit_events
  belongs_to :outbound_attempt, inverse_of: :workflow_audit_events, optional: true

  validates :event_type, presence: true

  # Prevents mutation after the audit record has been persisted.
  #
  # @return [Boolean] whether the event is read-only
  def readonly?
    persisted? || super
  end
end
