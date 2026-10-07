require "rails_helper"

RSpec.describe "WorkflowAuditEvent", type: :model do
  describe "immutability" do
    it "returns read-only when an existing event is changed" do
      event = create(:workflow_audit_event)

      expect { event.update!(details: { worker_id: "worker-2" }) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "returns read-only when an existing event is destroyed" do
      event = create(:workflow_audit_event)

      expect { event.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
