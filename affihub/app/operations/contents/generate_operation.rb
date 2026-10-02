# frozen_string_literal: true

class Contents::GenerateOperation < MainOperation
  attr_reader :content, :prompt

  # @param params [Hash] :current_user, :product_id, and optional :tone/:provider
  # @return [void]
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
    @product_id = params[:product_id]
    @tone = params[:tone]
    @provider = params[:provider] || AIProviders::Resolver.default
  end

  # Generates copy for a product owned by the current user and persists a content draft.
  #
  # @return [void]
  def call
    step_load_product
    return if error?

    step_build_prompt
    step_send_prompt
    step_create_content unless error?
  end

  private

  # Loads only products owned by the authenticated user.
  #
  # @return [void]
  def step_load_product
    @product = current_user&.products&.find_by(id: @product_id)
    errors.add(:base, "Product không tồn tại hoặc không thuộc tài khoản của bạn") unless @product
  end

  # Builds the provider prompt from the selected product's source facts.
  #
  # @return [void]
  def step_build_prompt
    @prompt = Contents::BuildPrompt.call(params: { product: @product, tone: @tone }).prompt
  end

  # Sends copy generation through the provider contract and translates provider failures.
  #
  # @return [void]
  def step_send_prompt
    connection = current_user.ai_connection
    raise AIConnection::DisconnectedError unless connection

    @response = @provider.send_prompt(connection:, prompt: @prompt)
  rescue AIConnection::DisconnectedError, AIProviders::Contract::InvalidCredentialsError
    errors.add(:base, "AI connection đã mất kết nối, cần kết nối lại")
  rescue AIProviders::Contract::TransportError
    errors.add(:base, "Không thể kết nối tới AI provider lúc này. Vui lòng thử lại")
  rescue AIProviders::Contract::ResponseError
    errors.add(:base, "AI provider không thể tạo nội dung lúc này. Vui lòng thử lại")
  end

  # Persists the provider's copy with source-owned product and affiliate URL values.
  #
  # @return [void]
  def step_create_content
    Content.transaction do
      @content = Content.create!(
        product: @product,
        user: current_user,
        body: Contents::GeneratedCopySanitizer.call(body: @response.fetch("output_text")),
        affiliate_url: @product.affiliate_url
      )
      @content.start_review!
    end
  rescue KeyError
    errors.add(:base, "AI provider returned no generated content")
  rescue ActiveRecord::RecordInvalid, Content::InvalidTransitionError
    @content = nil
    errors.add(:base, "Không thể đưa nội dung vào trạng thái review")
  end
end
