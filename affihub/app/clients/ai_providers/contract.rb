# frozen_string_literal: true

class AIProviders::Contract
  class Error < StandardError; end
  class InvalidCredentialsError < Error; end
  class TransportError < Error; end
  class ResponseError < Error; end

  # Returns the provider-specific lead time used to refresh an access token.
  #
  # @return [ActiveSupport::Duration] time before expiry when refresh should begin
  def refresh_lead
    raise NotImplementedError
  end

  # Builds the provider authorization URL for an OAuth flow.
  #
  # @param state [String] OAuth state value
  # @param code_challenge [String] PKCE S256 challenge
  # @return [String] provider authorization URL
  def build_authorize_url(state:, code_challenge:)
    raise NotImplementedError
  end

  # Exchanges an OAuth code for credentials and provider account context.
  #
  # @param code [String] OAuth authorization code
  # @param code_verifier [String] PKCE verifier for the authorization request
  # @return [Hash] token fields and verified provider account context
  def exchange_token(code:, code_verifier:)
    raise NotImplementedError
  end

  # Rotates provider credentials using the current refresh token.
  #
  # @param refresh_token [String] current refresh token
  # @return [Hash] rotated access token, refresh token, and expiry
  def refresh_token(refresh_token:)
    raise NotImplementedError
  end

  # Sends a prompt after ensuring the connection's credentials are usable and fresh.
  #
  # @param connection [AIConnection] connection supplying provider credentials
  # @param prompt [String] prompt sent to the provider
  # @return [Hash] provider response containing generated output text
  def send_prompt(connection:, prompt:)
    raise NotImplementedError
  end
end
