# frozen_string_literal: true

class Contents::UpdateOperation < MainOperation
  attr_reader :content

  # @param params [Hash] :current_user, :id, and editable :body
  # @return [void]
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
    @content_id = params[:id]
    @form = Contents::UpdateForm.new(params.slice(:body))
  end

  # Updates a review content's body without changing its product or affiliate URL.
  #
  # @return [void]
  def call
    step_load_content
    return if error?

    step_validate_review_state
    return if error?

    step_validate_form
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

  # Rejects edits after review has ended.
  #
  # @return [void]
  def step_validate_review_state
    errors.add(:base, "Chỉ có thể chỉnh sửa Content đang ở trạng thái review") unless @content.status_review?
  end

  # Validates the editable copy field.
  #
  # @return [void]
  def step_validate_form
    return if @form.valid?

    errors.merge!(@form.errors)
  end

  # Saves only the body attribute accepted by the form.
  #
  # @return [void]
  def step_update_content
    @content.update(@form.attributes)
    errors.merge!(@content.errors) unless @content.errors.empty?
  end
end
