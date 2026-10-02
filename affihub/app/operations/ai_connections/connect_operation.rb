# frozen_string_literal: true

require "socket"
require "digest"

# Binds the port-1455 callback listener SYNCHRONOUSLY (so a busy port fails before any
# redirect happens), then spawns CodexCallbackListener in a background Thread and returns the
# auth.openai.com authorize_url for the controller to redirect to. See design.md Decision 1.
class AIConnections::ConnectOperation < MainOperation
  # @return [String, nil] the auth.openai.com authorize_url to redirect the user to, once #call
  #   has run successfully; nil if binding the callback port failed
  attr_reader :authorize_url

  # @param params [Hash] :current_user (required), :provider (optional provider contract),
  #   :listener_timeout (optional, seconds — overridable for tests)
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
    @provider = params[:provider] || AIProviders::Resolver.default
    @listener_timeout = params[:listener_timeout].present? ? params[:listener_timeout].to_f : CodexCallbackListener::DEFAULT_TIMEOUT
  end

  # @return [void]
  def call
    step_bind_callback_listener_port
    step_build_authorize_url unless error?
    step_spawn_callback_listener unless error?
  rescue StandardError => error
    @server&.close unless @listener_thread
    @authorize_url = nil
    Rails.logger.warn("[AIConnections::ConnectOperation] setup failed error_class=#{error.class.name}")
    errors.add(:base, "Không thể khởi tạo kết nối AI. Vui lòng thử lại")
  end

  private

  # Binds the configured callback endpoint synchronously (on the Puma request thread), so a busy port is reported as
  # a form error immediately instead of failing silently inside the background listener Thread.
  #
  # @return [void]
  def step_bind_callback_listener_port
    callback_host = Addrinfo.getaddrinfo(
      CodexClient::CONFIG.callback_host,
      CodexClient::CONFIG.callback_port,
      :INET,
      :STREAM
    ).first.ip_address
    @server = TCPServer.new(callback_host, CodexClient::CONFIG.callback_port)
  rescue Errno::EADDRINUSE
    errors.add(:base, "Port #{CodexClient::CONFIG.callback_port} đang bận, đóng ứng dụng khác đang dùng port này")
  end

  # Generates the OAuth state + PKCE pair and builds the authorize_url from them.
  #
  # @return [void]
  def step_build_authorize_url
    @state = SecureRandom.hex(16)
    @code_verifier = SecureRandom.urlsafe_base64(32)
    code_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@code_verifier), padding: false)
    @authorize_url = @provider.build_authorize_url(state: @state, code_challenge: code_challenge)
  end

  # Spawns CodexCallbackListener in a background Thread, handing off the already-bound socket.
  #
  # @return [Thread] the spawned listener thread (not awaited — fire and forget)
  def step_spawn_callback_listener
    server = @server
    state = @state
    code_verifier = @code_verifier
    user_id = current_user.id
    provider = @provider
    timeout = @listener_timeout

    @listener_thread = Thread.new do
      CodexCallbackListener.new(
        server: server,
        state: state,
        code_verifier: code_verifier,
        user_id: user_id,
        provider: provider,
        timeout: timeout
      ).call
    end
  end
end
