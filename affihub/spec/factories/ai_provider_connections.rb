FactoryBot.define do
  factory :ai_provider_connection do
    provider { "gemini" }
    provider_subject { "google-subject-#{SecureRandom.hex(8)}" }
    provider_client_id { "gemini-web-client" }
    account_email { "creator@example.com" }
    display_name { "AffiHub Creator" }
    access_token { "provider-access-token" }
    refresh_token { "provider-refresh-token" }
    id_token { "provider-id-token" }
    access_token_expires_at { 1.hour.from_now }
    scopes { %w[openid email profile https://www.googleapis.com/auth/generative-language.retriever] }
    available_models do
      [
        {
          "slug" => "models/gemini-3.5-flash-lite",
          "display_name" => "Gemini 3.5 Flash-Lite"
        }
      ]
    end
    selected_model { "models/gemini-3.5-flash-lite" }
    last_verified_at { Time.current }
  end
end
