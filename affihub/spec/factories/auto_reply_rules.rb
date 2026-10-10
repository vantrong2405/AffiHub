FactoryBot.define do
  factory :auto_reply_rule do
    association :social_destination
    rule_type do
      Rails.application.config_for(:video_workflow).deep_symbolize_keys
        .fetch(:auto_responder)
        .fetch(:rule_types)
        .fetch(:default)
    end
    reply_text { "Cảm ơn bạn đã quan tâm." }
  end
end
