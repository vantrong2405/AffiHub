FactoryBot.define do
  factory :auto_reply_event do
    association :social_destination
    source { social_destination.provider }
    event_type do
      Rails.application.config_for(:video_workflow).deep_symbolize_keys
        .fetch(:auto_responder)
        .fetch(:comment_event_type)
    end
    sequence(:provider_comment_id) { |number| "provider-comment-#{number}" }
    comment_text { "Mẫu này còn hàng không?" }
  end
end
