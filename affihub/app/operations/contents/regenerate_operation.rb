# frozen_string_literal: true

class Contents::RegenerateOperation < MainOperation
  attr_reader :content

  # @param params [Hash] :current_user, :id, and optional :tone/:provider
  # @return [void]
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
    @content_id = params[:id]
    @tone = params[:tone]
    @provider = params[:provider] || AIProviders::Resolver.default
  end

  # Regenerates the selected content row without changing its product or affiliate URL.
  #
  # @return [void]
  def call
    step_load_content
    return if error?

    step_validate_review_state
    return if error?

    step_build_prompt
    step_send_prompt
    step_update_content unless error?
  end

  private

  # Loads only content owned by the current user.
  #
  # @return [void]
  def step_load_content
    @content = Content.find_by(id: @content_id, user_id: current_user&.id)
    errors.add(:base, "Content không tồn tại hoặc không thuộc tài khoản của bạn") unless @content
  end

  # Allows regeneration of review/rejected content and keeps approved rows terminal.
  #
  # @return [void]
  def step_validate_review_state
    return if @content.status_review? || @content.status_rejected?

    message = if @content.status_approved?
      "Content đã được approve, không thể regenerate. Hãy tạo Content mới từ Product."
    else
      "Chỉ có thể regenerate Content đang ở trạng thái review hoặc rejected"
    end
    errors.add(:base, message)
  end

  # Builds a prompt from the product associated with the selected content row.
  #
  # @return [void]
  def step_build_prompt
    @prompt = Contents::BuildPrompt.call(params: { product: @content.product, tone: @tone }).prompt
  end

  # Sends the provider request without changing content before it succeeds.
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

  # Updates only this content row and returns rejected drafts to review atomically.
  #
  # @return [void]
  def step_update_content
    Content.transaction do
      body = Contents::GeneratedCopySanitizer.call(body: @response.fetch("output_text"))
      @content.update!(body: body, generation_count: @content.generation_count + 1)
      @content.start_review! if @content.status_rejected?
    end
  rescue KeyError
    errors.add(:base, "AI provider returned no generated content")
  rescue ActiveRecord::RecordInvalid, Content::InvalidTransitionError
    errors.add(:base, "Không thể cập nhật nội dung được tạo lại")
  end
end
