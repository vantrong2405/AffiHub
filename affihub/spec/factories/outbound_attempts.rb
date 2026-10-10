FactoryBot.define do
  factory :outbound_attempt do
    association :workflow_run
    attempt_id { SecureRandom.uuid }
    attempt_number { 1 }
    stage { "publish" }
    status { "prepared" }
    request_timeout_at { 30.seconds.from_now }
  end
end
