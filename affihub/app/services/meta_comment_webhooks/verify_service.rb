class MetaCommentWebhooks::VerifyService < ApplicationService
  attr_reader :challenge

  # Initializes Meta's webhook subscription handshake verification.
  #
  # @param mode [String] the requested webhook handshake mode
  # @param verify_token [String] the token sent by Meta
  # @param challenge [String] the challenge Meta expects echoed
  # @return [MetaCommentWebhooks::VerifyService] the configured service
  def initialize(mode:, verify_token:, challenge:)
    @mode = mode.to_s
    @verify_token = verify_token.to_s
    @challenge = challenge.to_s
    super()
  end

  # Accepts only a subscribe handshake signed with the configured verify token.
  #
  # @return [Boolean] whether Meta's challenge may be returned
  def call
    step_verify_handshake
    success?
  end

  private

  def step_verify_handshake
    expected_token = Rails.application.credentials.dig(:meta, :webhook_verify_token).to_s
    valid_mode = @mode == "subscribe"
    valid_token = step_secure_token_match?(expected_token, @verify_token)
    return step_fail!("Không xác minh được webhook Meta.") unless valid_mode && valid_token && @challenge.present?

    step_succeed!
  end

  def step_secure_token_match?(expected_token, provided_token)
    return false if expected_token.blank? || provided_token.blank? || expected_token.bytesize != provided_token.bytesize

    ActiveSupport::SecurityUtils.secure_compare(expected_token, provided_token)
  end
end
