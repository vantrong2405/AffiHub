FactoryBot.define do
  factory :workflow_audit_event do
    association :workflow_run
    event_type { "claimed" }
    details { { worker_id: "worker-1" } }
  end
end
