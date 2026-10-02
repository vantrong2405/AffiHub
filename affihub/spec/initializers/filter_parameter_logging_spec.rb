# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Codex credential log filtering" do
  it "filters any parameter whose key contains access_token/refresh_token/id_token from logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter(access_token: "secret-a", refresh_token: "secret-r", id_token: "secret-i")

    expect(filtered).to eq(access_token: "[FILTERED]", refresh_token: "[FILTERED]", id_token: "[FILTERED]")
  end

  it "never writes a raw access_token/refresh_token/id_token to the Rails log during a real Codex call" do
    ai_connection = create(:ai_connection, access_token: "super-secret-access-token", refresh_token: "super-secret-refresh-token", id_token: "super-secret-id-token", access_token_expires_at: 1.hour.from_now)
    stub_request(:post, "https://chatgpt.com/backend-api/codex/responses")
      .to_return(status: 200, body: { output_text: "pong" }.to_json, headers: { "Content-Type" => "application/json" })

    log_output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(log_output)

    begin
      AIConnections::TestConnectionOperation.call(params: { ai_connection: ai_connection })
    ensure
      Rails.logger = original_logger
    end

    expect(log_output.string).not_to include("super-secret-access-token")
    expect(log_output.string).not_to include("super-secret-refresh-token")
    expect(log_output.string).not_to include("super-secret-id-token")
  end
end
