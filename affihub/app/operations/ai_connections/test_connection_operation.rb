# frozen_string_literal: true

# Sends a prompt through the AI provider contract, which ensures credentials are usable and fresh.
class AIConnections::TestConnectionOperation < MainOperation
  PROMPT = "Say hello in one short sentence."

  # @return [Hash, nil] the parsed Codex response after a successful #call, nil on failure
  attr_reader :response

  # @param params [Hash] :current_user (required unless :ai_connection given), :ai_connection
  #   (optional, defaults to current_user.ai_connection), :provider (optional provider contract)
  # @return [void]
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
    @ai_connection = params[:ai_connection] || current_user&.ai_connection
    @provider = params[:provider] || AIProviders::Resolver.default
  end

  # @return [void]
  def call
    step_send_prompt
  end

  private

  # Sends the test prompt through the provider contract and maps provider failures to operation errors.
  #
  # @return [void]
  def step_send_prompt
    raise AIConnection::DisconnectedError if @ai_connection.nil?

    @response = @provider.send_prompt(connection: @ai_connection, prompt: PROMPT)
  rescue AIConnection::DisconnectedError, AIProviders::Contract::InvalidCredentialsError
    disconnected = @ai_connection.nil? || @ai_connection.reload.status_disconnected?
    message = disconnected ? "AI connection đã mất kết nối, cần kết nối lại" : "Không thể làm mới kết nối AI lúc này. Vui lòng thử lại"
    errors.add(:base, message)
  rescue AIProviders::Contract::TransportError
    errors.add(:base, "Không thể kết nối tới AI provider lúc này. Vui lòng thử lại")
  rescue AIProviders::Contract::ResponseError
    errors.add(:base, "AI provider không chấp nhận yêu cầu kiểm tra kết nối")
  end
end
