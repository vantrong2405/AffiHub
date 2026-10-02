# frozen_string_literal: true

require "rails_helper"
require "socket"

RSpec.describe CodexCallbackListener do
  def bound_server
    TCPServer.new("127.0.0.1", 0)
  end

  def get(port, query)
    Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/auth/callback?#{query}"))
  end

  def signed_id_token(signing_key: nil)
    trusted_key = OpenSSL::PKey::RSA.generate(2048)
    jwk = JWT::JWK.new(trusted_key, kid: "callback-test-key", use: "sig", alg: "RS256")
    stub_request(:get, CodexClient::CONFIG.jwks_url).to_return(
      status: 200,
      body: JWT::JWK::Set.new(jwk).export.to_json,
      headers: { "Content-Type" => "application/json" }
    )
    claims = {
      "iss" => CodexClient::CONFIG.issuer,
      "sub" => "callback-subject",
      "aud" => CodexClient::CONFIG.client_id,
      "exp" => 10.minutes.from_now.to_i,
      "iat" => Time.current.to_i,
      "https://api.openai.com/auth" => {
        "chatgpt_account_id" => "account-123",
        "chatgpt_plan_type" => "plus"
      }
    }

    JWT.encode(claims, signing_key || trusted_key, "RS256", kid: "callback-test-key")
  end

  it "exchanges the code for tokens, creates a connected AIConnection, and redirects to callback_result with outcome=success" do
    user = create(:user)
    server = bound_server
    port = server.addr[1]
    id_token = signed_id_token
    stub_request(:post, "https://auth.openai.com/oauth/token").to_return(
      status: 200,
      body: { access_token: "a", refresh_token: "r", id_token: id_token, expires_in: 3600 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    thread = Thread.new { described_class.new(server: server, state: "state-1", code_verifier: "verifier", user_id: user.id, timeout: 5).call }
    response = get(port, "code=abc&state=state-1")
    thread.join(5)

    expect(response.code).to eq("302")
    expect(response["Location"]).to eq("http://localhost:4000/ai_connection/callback_result?outcome=success")
    connection = AIConnection.find_by(user_id: user.id)
    expect(connection.status_connected?).to eq(true)
    expect(connection.chatgpt_account_id).to eq("account-123")
    expect(connection.chatgpt_plan_type).to eq("plus")
    expect(connection.connected_at).to be_within(5.seconds).of(Time.current)
  end

  it "rejects a state mismatch without exchanging the code, and does not create an AIConnection" do
    user = create(:user)
    server = bound_server
    port = server.addr[1]

    thread = Thread.new { described_class.new(server: server, state: "expected-state", code_verifier: "verifier", user_id: user.id, timeout: 5).call }
    response = get(port, "code=abc&state=wrong-state")
    thread.join(5)

    expect(response.code).to eq("302")
    expect(response["Location"]).to eq("http://localhost:4000/ai_connection/callback_result?outcome=error&reason=state_mismatch")
    expect(AIConnection.find_by(user_id: user.id)).to be_nil
  end

  it "redirects with outcome=error reason=exchange_failed when token exchange fails, without creating an AIConnection" do
    user = create(:user)
    server = bound_server
    port = server.addr[1]
    stub_request(:post, "https://auth.openai.com/oauth/token").to_return(status: 400, body: { error: "invalid_grant" }.to_json)

    thread = Thread.new { described_class.new(server: server, state: "state-1", code_verifier: "verifier", user_id: user.id, timeout: 5).call }
    response = get(port, "code=abc&state=state-1")
    thread.join(5)

    expect(response["Location"]).to eq("http://localhost:4000/ai_connection/callback_result?outcome=error&reason=exchange_failed")
    expect(AIConnection.find_by(user_id: user.id)).to be_nil
  end

  it "preserves the existing connection when OAuth reconnect token exchange fails" do
    user = create(:user)
    connection = create(
      :ai_connection,
      user: user,
      access_token: "existing-access-token",
      refresh_token: "existing-refresh-token",
      id_token: "existing-id-token",
      status: "connected"
    )
    previous_connected_at = 3.days.ago
    connection.update_column(:connected_at, previous_connected_at)
    server = bound_server
    port = server.addr[1]
    stub_request(:post, "https://auth.openai.com/oauth/token").to_return(status: 400, body: { error: "invalid_grant" }.to_json)

    thread = Thread.new { described_class.new(server: server, state: "state-1", code_verifier: "verifier", user_id: user.id, timeout: 5).call }
    response = get(port, "code=abc&state=state-1")
    thread.join(5)
    connection.reload

    expect(response["Location"]).to eq("http://localhost:4000/ai_connection/callback_result?outcome=error&reason=exchange_failed")
    expect(connection.access_token).to eq("existing-access-token")
    expect(connection.refresh_token).to eq("existing-refresh-token")
    expect(connection.id_token).to eq("existing-id-token")
    expect(connection.status).to eq("connected")
    expect(connection.connected_at).to eq(previous_connected_at)
  end

  it "does not persist or use account context from an ID token with an invalid signature" do
    user = create(:user)
    server = bound_server
    port = server.addr[1]
    id_token = signed_id_token(signing_key: OpenSSL::PKey::RSA.generate(2048))
    stub_request(:post, "https://auth.openai.com/oauth/token").to_return(
      status: 200,
      body: { access_token: "untrusted-access-token", refresh_token: "untrusted-refresh-token", id_token:, expires_in: 3600 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    thread = Thread.new { described_class.new(server: server, state: "state-1", code_verifier: "verifier", user_id: user.id, timeout: 5).call }
    response = get(port, "code=abc&state=state-1")
    thread.join(5)

    expect(response["Location"]).to eq("http://localhost:4000/ai_connection/callback_result?outcome=error&reason=exchange_failed")
    expect(AIConnection.find_by(user: user)).to be_nil
    expect(a_request(:post, "https://chatgpt.com/backend-api/codex/responses")).not_to have_been_made
  end

  it "does not exchange a callback without an authorization code" do
    user = create(:user)
    server = bound_server
    port = server.addr[1]

    thread = Thread.new { described_class.new(server: server, state: "state-1", code_verifier: "verifier", user_id: user.id, timeout: 5).call }
    response = get(port, "state=state-1")
    thread.join(5)

    expect(response["Location"]).to eq("http://localhost:4000/ai_connection/callback_result?outcome=error&reason=authorization_failed")
    expect(a_request(:post, "https://auth.openai.com/oauth/token")).not_to have_been_made
    expect(AIConnection.find_by(user_id: user.id)).to be_nil
  end

  it "does not exchange a callback containing an OAuth error" do
    user = create(:user)
    server = bound_server
    port = server.addr[1]

    thread = Thread.new { described_class.new(server: server, state: "state-1", code_verifier: "verifier", user_id: user.id, timeout: 5).call }
    response = get(port, "state=state-1&error=access_denied")
    thread.join(5)

    expect(response["Location"]).to eq("http://localhost:4000/ai_connection/callback_result?outcome=error&reason=authorization_failed")
    expect(a_request(:post, "https://auth.openai.com/oauth/token")).not_to have_been_made
    expect(AIConnection.find_by(user_id: user.id)).to be_nil
  end

  it "redirects safely when token exchange times out" do
    user = create(:user)
    server = bound_server
    port = server.addr[1]
    stub_request(:post, "https://auth.openai.com/oauth/token").to_timeout

    thread = Thread.new { described_class.new(server: server, state: "state-1", code_verifier: "verifier", user_id: user.id, timeout: 5).call }
    response = get(port, "code=abc&state=state-1")
    thread.join(5)

    expect(response["Location"]).to eq("http://localhost:4000/ai_connection/callback_result?outcome=error&reason=exchange_failed")
    expect(AIConnection.find_by(user_id: user.id)).to be_nil
  end

  it "redirects safely when token exchange returns invalid JSON" do
    user = create(:user)
    server = bound_server
    port = server.addr[1]
    stub_request(:post, "https://auth.openai.com/oauth/token").to_return(status: 200, body: "not-json")

    thread = Thread.new { described_class.new(server: server, state: "state-1", code_verifier: "verifier", user_id: user.id, timeout: 5).call }
    response = get(port, "code=abc&state=state-1")
    thread.join(5)

    expect(response["Location"]).to eq("http://localhost:4000/ai_connection/callback_result?outcome=error&reason=exchange_failed")
    expect(AIConnection.find_by(user_id: user.id)).to be_nil
  end

  it "does not persist a connection when the successful token response is incomplete" do
    user = create(:user)
    server = bound_server
    port = server.addr[1]
    stub_request(:post, "https://auth.openai.com/oauth/token").to_return(
      status: 200,
      body: { access_token: "access-token", id_token: signed_id_token, expires_in: 3600 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    thread = Thread.new { described_class.new(server: server, state: "state-1", code_verifier: "verifier", user_id: user.id, timeout: 5).call }
    response = get(port, "code=abc&state=state-1")
    thread.join(5)

    expect(response["Location"]).to eq("http://localhost:4000/ai_connection/callback_result?outcome=error&reason=exchange_failed")
    expect(AIConnection.find_by(user_id: user.id)).to be_nil
  end

  it "redirects safely when persisting exchanged tokens fails" do
    server = bound_server
    port = server.addr[1]
    id_token = signed_id_token
    stub_request(:post, "https://auth.openai.com/oauth/token").to_return(
      status: 200,
      body: { access_token: "a", refresh_token: "r", id_token:, expires_in: 3600 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    thread = Thread.new { described_class.new(server: server, state: "state-1", code_verifier: "verifier", user_id: -1, timeout: 5).call }
    response = get(port, "code=abc&state=state-1")
    thread.join(5)

    expect(response["Location"]).to eq("http://localhost:4000/ai_connection/callback_result?outcome=error&reason=exchange_failed")
    expect(AIConnection.count).to eq(0)
  end

  it "exchanges concurrent callbacks only once without interrupting the winning response" do
    user = create(:user)
    server = bound_server
    port = server.addr[1]
    exchange_started = Queue.new
    finish_exchange = Queue.new
    request_count = 0
    request_mutex = Mutex.new
    id_token = signed_id_token
    exchange = stub_request(:post, "https://auth.openai.com/oauth/token").to_return do
      current_request = request_mutex.synchronize { request_count += 1 }
      if current_request == 1
        exchange_started << true
        finish_exchange.pop
      end
      { status: 200, body: { access_token: "a", refresh_token: "r", id_token:, expires_in: 3600 }.to_json, headers: { "Content-Type" => "application/json" } }
    end

    listener = Thread.new { described_class.new(server: server, state: "state-1", code_verifier: "verifier", user_id: user.id, timeout: 5).call }
    winning_callback = Thread.new { get(port, "code=abc&state=state-1") }
    exchange_started.pop
    second_response = get(port, "code=abc&state=state-1")
    finish_exchange << true
    winning_response = winning_callback.value
    listener.join(5)

    expect(second_response.code).to eq("204")
    expect(winning_response["Location"]).to eq("http://localhost:4000/ai_connection/callback_result?outcome=success")
    expect(exchange).to have_been_requested.once
    expect(AIConnection.where(user: user).count).to eq(1)
  ensure
    finish_exchange << true if finish_exchange && finish_exchange.empty?
  end

  it "ignores a second callback request after the first has already been handled" do
    user = create(:user)
    server = bound_server
    port = server.addr[1]
    id_token = signed_id_token
    stub_request(:post, "https://auth.openai.com/oauth/token").to_return(
      status: 200,
      body: { access_token: "a", refresh_token: "r", id_token:, expires_in: 3600 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    thread = Thread.new { described_class.new(server: server, state: "state-1", code_verifier: "verifier", user_id: user.id, timeout: 5).call }
    first = get(port, "code=abc&state=state-1")
    second = begin
      get(port, "code=abc&state=state-1")
    rescue StandardError
      # Server may already be mid-shutdown (single-request listener) by the time
      # the second request arrives — connection-level failure also proves it was
      # never processed a second time.
      nil
    end
    thread.join(5)

    expect(first.code).to eq("302")
    expect(second.nil? || second.code == "204").to eq(true)
    expect(AIConnection.where(user_id: user.id).count).to eq(1)
  end

  it "times out and shuts itself down without hanging when no callback ever arrives" do
    server = bound_server

    result = described_class.new(server: server, state: "state-1", code_verifier: "verifier", user_id: 1, timeout: 0.3).call

    expect(result).to eq(false)
    expect(server.closed?).to eq(true)
  end
end
