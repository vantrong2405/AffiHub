# frozen_string_literal: true

require "webrick"
require "timeout"

# Handles exactly one GET /auth/callback request on an already-bound TCPServer, then shuts
# itself down. Runs inside a Thread spawned by AIConnections::ConnectOperation — see
# docs/reference-analysis/ai-connection.md and design.md Decision 1 for why the bind happens
# synchronously in the caller instead of here.
class CodexCallbackListener
  CONFIG = Rails.application.config_for(:codex)
  CALLBACK_PATH = CONFIG.callback_path
  DEFAULT_TIMEOUT = CONFIG.callback_timeout_seconds
  CALLBACK_RESULT_URL = "#{CONFIG.app_base_url}/ai_connection/callback_result"

  # @param server [TCPServer] an already-bound (caller's responsibility) socket to listen on
  # @param state [String] the OAuth state to require a match against on callback
  # @param code_verifier [String] the PKCE code_verifier to use when exchanging the code
  # @param user_id [Integer] the user to attach the resulting AIConnection to
  # @param provider [AIProviders::Contract] provider contract used to exchange the code
  # @param timeout [Numeric] seconds to wait for a callback before giving up
  def initialize(server:, state:, code_verifier:, user_id:, provider: AIProviders::Resolver.default, timeout: DEFAULT_TIMEOUT)
    @server = server
    @state = state
    @code_verifier = code_verifier
    @user_id = user_id
    @provider = provider
    @timeout = timeout
    @callback_claimed = false
    @callback_mutex = Mutex.new
  end

  # Blocks the calling Thread until the callback is handled once, or until timeout.
  #
  # @return [Boolean] true if a callback was handled, false if it timed out first
  def call
    http_server = build_http_server

    Timeout.timeout(@timeout) { http_server.start }
    true
  rescue Timeout::Error
    Rails.logger.info("[CodexCallbackListener] timed out after #{@timeout}s waiting for OAuth callback")
    false
  ensure
    http_server&.shutdown
    @server.close unless @server.closed?
  end

  private

  # @return [WEBrick::HTTPServer] a server using the caller's pre-bound socket (DoNotListen:
  #   true means WEBrick never binds its own), mounted on CALLBACK_PATH
  def build_http_server
    http_server = WEBrick::HTTPServer.new(
      DoNotListen: true,
      Logger: WEBrick::Log.new(File::NULL),
      AccessLog: []
    )
    http_server.listeners << @server
    http_server.mount_proc(CALLBACK_PATH) { |req, res| handle_callback(req, res, http_server) }
    http_server
  end

  # WEBrick request handler for CALLBACK_PATH. Ignores any request after the first (guards
  # against double-callback), verifies state, then exchanges the code or rejects it.
  #
  # @param req [WEBrick::HTTPRequest] the incoming callback request
  # @param res [WEBrick::HTTPResponse] the response to write a redirect into
  # @param http_server [WEBrick::HTTPServer] the server to shut down after handling
  # @return [void]
  def handle_callback(req, res, http_server)
    unless claim_callback
      res.status = 204
      return
    end
    begin
      if req.query["state"] != @state
        redirect_to_result(res, outcome: "error", reason: "state_mismatch")
      elsif req.query["error"].present? || req.query["code"].blank?
        redirect_to_result(res, outcome: "error", reason: "authorization_failed")
      else
        exchange_and_persist(req.query["code"], res)
      end
    ensure
      Thread.new { http_server.shutdown }
    end
  end

  # Atomically claims the listener for one callback and keeps it claimed afterward.
  #
  # @return [Boolean] true only for the first callback request
  def claim_callback
    @callback_mutex.synchronize do
      next false if @callback_claimed

      @callback_claimed = true
    end
  end

  # @param code [String] the authorization code from the callback query string
  # @param res [WEBrick::HTTPResponse] the response to write a redirect into
  # @return [void]
  def exchange_and_persist(code, res)
    tokens = @provider.exchange_token(code: code, code_verifier: @code_verifier)
    persist_ai_connection!(tokens)
    redirect_to_result(res, outcome: "success")
  rescue AIProviders::Contract::Error, ActiveRecord::ActiveRecordError => error
    Rails.logger.warn("[CodexCallbackListener] callback failed error_class=#{error.class.name}")
    redirect_to_result(res, outcome: "error", reason: "exchange_failed")
  end

  # Creates or updates the user's AIConnection with the exchanged tokens. Runs in a background
  # Thread (not a Puma request thread), so it must explicitly check out a DB connection.
  #
  # @param tokens [Hash] parsed token response from CodexClient#exchange_token
  # @return [void]
  def persist_ai_connection!(tokens)
    ActiveRecord::Base.connection_pool.with_connection do
      AIConnection.transaction do
        connection = AIConnection.lock.find_or_initialize_by(user_id: @user_id)
        connection.update!(
          access_token: tokens["access_token"],
          refresh_token: tokens["refresh_token"],
          id_token: tokens["id_token"],
          access_token_expires_at: Time.current + tokens["expires_in"].to_i.seconds,
          chatgpt_account_id: tokens["account_id"],
          chatgpt_plan_type: tokens["plan_type"],
          status: "connected",
          connected_at: Time.current
        )
      end
    end
  end

  # @param res [WEBrick::HTTPResponse] the response to write the redirect into
  # @param outcome ["success", "error"] the result to report to AIConnectionsController#callback_result
  # @param reason [String, nil] machine-readable failure reason, only set when outcome is "error"
  # @return [void]
  def redirect_to_result(res, outcome:, reason: nil)
    query = URI.encode_www_form(reason ? { outcome: outcome, reason: reason } : { outcome: outcome })
    res.status = 302
    res["Location"] = "#{CALLBACK_RESULT_URL}?#{query}"
  end
end
