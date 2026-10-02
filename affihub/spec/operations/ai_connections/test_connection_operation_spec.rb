# frozen_string_literal: true

require "rails_helper"

RSpec.describe AIConnections::TestConnectionOperation do
  it "refreshes the expired access_token before sending the prompt, and the prompt request carries the NEW token" do
    ai_connection = create(:ai_connection, access_token: "stale-token", refresh_token: "refresh-1", access_token_expires_at: nil, chatgpt_account_id: "acct-1")
    stub_request(:post, "https://auth.openai.com/oauth/token").to_return(
      status: 200,
      body: { access_token: "fresh-token", refresh_token: "refresh-2", expires_in: 3600 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
      prompt_stub = stub_request(:post, "https://chatgpt.com/backend-api/codex/responses")
        .with(headers: { "Authorization" => "Bearer fresh-token" })
        .to_return(
          status: 200,
          body: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"pong\"}\n\ndata: {\"type\":\"response.completed\"}\n\n",
          headers: { "Content-Type" => "text/event-stream" }
        )

    operator = described_class.call(params: { ai_connection: ai_connection })

    expect(operator.success?).to eq(true)
    expect(operator.response).to eq("output_text" => "pong")
    expect(prompt_stub).to have_been_requested
  end

  it "does not call send_prompt and fails clearly when the refresh itself fails" do
    ai_connection = create(:ai_connection, access_token: "stale-token", refresh_token: "already-used-token", access_token_expires_at: nil)
    stub_request(:post, "https://auth.openai.com/oauth/token").to_return(status: 400, body: { error: "invalid_grant" }.to_json)

    operator = described_class.call(params: { ai_connection: ai_connection })

    expect(operator.success?).to eq(false)
    expect(operator.errors.full_messages.to_sentence).to eq("AI connection đã mất kết nối, cần kết nối lại")
    expect(a_request(:post, "https://chatgpt.com/backend-api/codex/responses")).not_to have_been_made
  end

  it "returns a failure when the Codex backend rejects the prompt" do
    ai_connection = create(:ai_connection, access_token: "fresh-token", access_token_expires_at: 1.hour.from_now, chatgpt_account_id: "acct-1")
    stub_request(:post, "https://chatgpt.com/backend-api/codex/responses")
      .to_return(status: 400, body: "bad request")

    operator = described_class.call(params: { ai_connection: ai_connection })

    expect(operator.success?).to eq(false)
    expect(operator.errors.full_messages.to_sentence).to eq("AI provider không chấp nhận yêu cầu kiểm tra kết nối")
  end

  it "does not send a prompt when the connection is disconnected" do
    ai_connection = create(:ai_connection, status: "disconnected", access_token_expires_at: 1.hour.from_now)

    operator = described_class.call(params: { ai_connection: ai_connection })

    expect(operator.success?).to eq(false)
    expect(a_request(:post, "https://chatgpt.com/backend-api/codex/responses")).not_to have_been_made
  end

  it "does not send a prompt when the access token is missing" do
    ai_connection = create(:ai_connection, access_token: nil, access_token_expires_at: 1.hour.from_now)

    operator = described_class.call(params: { ai_connection: ai_connection })

    expect(operator.success?).to eq(false)
    expect(a_request(:post, "https://chatgpt.com/backend-api/codex/responses")).not_to have_been_made
  end

  it "does not send a prompt when an expired access token has no refresh token" do
    ai_connection = create(:ai_connection, access_token: "stale-token", refresh_token: nil, access_token_expires_at: nil)

    operator = described_class.call(params: { ai_connection: ai_connection })

    expect(operator.success?).to eq(false)
    expect(a_request(:post, "https://chatgpt.com/backend-api/codex/responses")).not_to have_been_made
  end

  it "preserves a usable connection and reports a retryable error when refresh times out" do
    ai_connection = create(:ai_connection, access_token: "existing-access-token", refresh_token: "existing-refresh-token", access_token_expires_at: nil)
    stub_request(:post, "https://auth.openai.com/oauth/token").to_timeout

    operator = described_class.call(params: { ai_connection: ai_connection })
    ai_connection.reload

    expect(operator.success?).to eq(false)
    expect(operator.errors.full_messages.to_sentence).to eq("Không thể làm mới kết nối AI lúc này. Vui lòng thử lại")
    expect(ai_connection.status).to eq("connected")
    expect(ai_connection.access_token).to eq("existing-access-token")
    expect(ai_connection.refresh_token).to eq("existing-refresh-token")
    expect(a_request(:post, "https://chatgpt.com/backend-api/codex/responses")).not_to have_been_made
  end

  it "sends the prompt through a provider contract implementation" do
    ai_connection = create(:ai_connection, access_token: "usable-access-token", access_token_expires_at: 1.hour.from_now, chatgpt_account_id: "account-123")
    prompt_request = stub_request(:post, "https://chatgpt.com/backend-api/codex/responses")
      .to_return(
        status: 200,
        body: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"pong\"}\n\ndata: {\"type\":\"response.completed\"}\n\n",
        headers: { "Content-Type" => "text/event-stream" }
      )

    operator = described_class.call(
      params: {
        ai_connection: ai_connection,
        provider: AIProviders::CodexAdapter.new
      }
    )

    expect(operator.success?).to eq(true)
    expect(operator.response).to eq("output_text" => "pong")
    expect(prompt_request).to have_been_requested.once
  end

  it "returns a friendly failure when the prompt request times out" do
    ai_connection = create(:ai_connection, access_token: "usable-access-token", access_token_expires_at: 1.hour.from_now, chatgpt_account_id: "account-123")
    stub_request(:post, "https://chatgpt.com/backend-api/codex/responses").to_timeout

    operator = described_class.call(params: { ai_connection: ai_connection })

    expect(operator.success?).to eq(false)
    expect(operator.errors.full_messages.to_sentence).to eq("Không thể kết nối tới AI provider lúc này. Vui lòng thử lại")
  end

  it "returns a friendly failure when the prompt connection is refused" do
    ai_connection = create(:ai_connection, access_token: "usable-access-token", access_token_expires_at: 1.hour.from_now, chatgpt_account_id: "account-123")
    stub_request(:post, "https://chatgpt.com/backend-api/codex/responses")
      .to_raise(Errno::ECONNREFUSED)

    operator = described_class.call(params: { ai_connection: ai_connection })

    expect(operator.success?).to eq(false)
    expect(operator.errors.full_messages.to_sentence).to eq("Không thể kết nối tới AI provider lúc này. Vui lòng thử lại")
  end
end
