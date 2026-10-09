FactoryBot.define do
  factory :schedule do
    association :render_version
    status { "active" }
    recurrence { "once" }
    time_zone { "Asia/Ho_Chi_Minh" }
    local_time { "09:00:00" }
    next_occurrence_at { 1.day.from_now }
  end

  factory :schedule_destination do
    association :schedule
    association :social_destination
    caption { "Caption theo destination" }
    consent_snapshot { {} }
  end

  factory :schedule_occurrence do
    association :schedule
    occurrence_key { "2026-10-10T02:00:00.000000Z" }
    scheduled_at { 1.day.from_now }
    dispatch_at { scheduled_at + 15.minutes }
    status { "scheduled" }
  end
end
