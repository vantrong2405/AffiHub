FactoryBot.define do
  factory :workflow_run do
    association :workflowable, factory: :source_asset
    operation_id { SecureRandom.uuid }
    operation { "source_inspection" }
    stage { "inspection" }
    status { "queued" }
  end
end
