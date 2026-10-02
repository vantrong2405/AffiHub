# frozen_string_literal: true

class AIProviders::CodexAdapter < AIProviders::Contract
  # @param client [CodexClient] HTTP client handling Codex-specific requests
  # @return [void]
  def initialize(client: CodexClient.new)
    @client = client
  end

  # Returns the configured Codex token refresh lead time.
  #
  # @return [ActiveSupport::Duration] time before expiry when refresh should begin
  def refresh_lead
    CodexClient::CONFIG.refresh_lead_minutes.minutes
  end

  # Builds the Codex OAuth authorization URL.
  #
  # @param state [String] OAuth state value
  # @param code_challenge [String] PKCE S256 challenge
  # @return [String] Codex authorization URL
  def build_authorize_url(state:, code_challenge:)
    @client.build_authorize_url(state:, code_challenge:)
  end

  # Exchanges an OAuth code and extracts the Codex account context from its ID token.
  #
  # @param code [String] OAuth authorization code
  # @param code_verifier [String] PKCE verifier for the authorization request
  # @return [Hash] token fields and Codex account context
  def exchange_token(code:, code_verifier:)
    tokens = @client.exchange_token(code:, code_verifier:)
    claims = verify_id_token!(tokens["id_token"])
    auth_claims = claims["https://api.openai.com/auth"]
    auth_claims = {} unless auth_claims.is_a?(Hash)
    account_id = auth_claims["chatgpt_account_id"]
    raise AIProviders::Contract::ResponseError, "Codex ID token is missing an account ID" if account_id.blank?

    tokens.merge(
      "account_id" => account_id,
      "plan_type" => auth_claims["chatgpt_plan_type"]
    )
  rescue JWT::Error => error
    raise AIProviders::Contract::ResponseError, "Codex ID token could not be verified: #{error.class.name}"
  rescue CodexClient::TransportError => error
    raise AIProviders::Contract::TransportError, error.message
  rescue CodexClient::TokenExchangeError => error
    raise AIProviders::Contract::ResponseError, error.message
  end

  # Rotates the Codex refresh token and maps Codex errors to provider-neutral errors.
  #
  # @param refresh_token [String] current refresh token
  # @return [Hash] rotated access token, refresh token, and expiry
  def refresh_token(refresh_token:)
    @client.refresh_token(refresh_token:)
  rescue CodexClient::InvalidRefreshTokenError => error
    raise AIProviders::Contract::InvalidCredentialsError, error.message
  rescue CodexClient::TransportError => error
    raise AIProviders::Contract::TransportError, error.message
  rescue CodexClient::TokenExchangeError => error
    raise AIProviders::Contract::ResponseError, error.message
  end

  # Sends a prompt with the fresh Codex access token and account header.
  #
  # @param connection [AIConnection] connection supplying Codex credentials
  # @param prompt [String] prompt sent to Codex
  # @return [Hash] Codex response containing generated output text
  def send_prompt(connection:, prompt:)
    connection.ensure_fresh_token!(provider: self)
    @client.send_prompt(
      access_token: connection.access_token,
      chatgpt_account_id: connection.chatgpt_account_id,
      prompt:
    )
  rescue CodexClient::TransportError => error
    raise AIProviders::Contract::TransportError, error.message
  rescue CodexClient::PromptRequestError => error
    raise AIProviders::Contract::ResponseError, error.message
  end

  private

  # Verifies the Codex ID token signature and required OpenID Connect claims.
  #
  # @param id_token [String, nil] raw Codex ID token
  # @return [Hash] verified ID token claims
  # @raise [AIProviders::Contract::ResponseError] when the ID token is missing
  def verify_id_token!(id_token)
    raise AIProviders::Contract::ResponseError, "Codex ID token is missing" if id_token.blank?

    jwks = JWT::JWK::Set.new(@client.fetch_jwks)
    jwks.select! { |key| key[:use] == "sig" && key[:alg] == CodexClient::CONFIG.id_token_algorithm }
    claims, = JWT.decode(
      id_token,
      nil,
      true,
      algorithms: [ CodexClient::CONFIG.id_token_algorithm ],
      jwks: jwks,
      iss: CodexClient::CONFIG.issuer,
      verify_iss: true,
      aud: CodexClient::CONFIG.client_id,
      verify_aud: true,
      leeway: CodexClient::CONFIG.id_token_leeway_seconds,
      required_claims: %w[iss sub aud exp iat]
    )
    claims
  end
end
