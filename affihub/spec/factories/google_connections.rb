FactoryBot.define do
  factory :google_connection do
    integration { "drive" }
    sequence(:google_account_id) { |number| "google-account-#{number}" }
    email { "creator@example.test" }
    access_token { "google-access-token" }
    refresh_token { "google-refresh-token" }
    access_token_expires_at { 1.hour.from_now }
    scopes { [ "openid", "email", "https://www.googleapis.com/auth/drive.file" ] }
    status { "connected" }
  end
end
