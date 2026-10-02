# frozen_string_literal: true

email = ENV["SEED_USER_EMAIL"]
password = ENV["SEED_USER_PASSWORD"]

if Rails.env.production? && (email.blank? || password.blank?)
  raise "SEED_USER_EMAIL and SEED_USER_PASSWORD must be set to seed a user in production"
end

email ||= "demo@affihub.local"
password ||= "password123"

User.find_or_create_by!(email: email) do |user|
  user.password = password
end
