FactoryBot.define do
  factory :ai_provider_connection do
    provider { "openai" }
    provider_subject { "openai-subject-#{SecureRandom.hex(8)}" }
    provider_client_id { "oaiapp_#{SecureRandom.hex(8)}" }
    account_email { "creator@example.com" }
    display_name { "AffiHub Creator" }
    access_token { "provider-access-token" }
    refresh_token { "provider-refresh-token" }
    id_token { "provider-id-token" }
    access_token_expires_at { 1.hour.from_now }
    scopes { %w[openid email profile offline_access resource.invoke chatgpt.tokens.use.direct] }
    available_models do
      [
        {
          "slug" => "gpt-6-luna",
          "display_name" => "GPT 6 Luna",
          "visibility" => "list"
        }
      ]
    end
    selected_model { "gpt-6-luna" }
    last_verified_at { Time.current }
  end
end
