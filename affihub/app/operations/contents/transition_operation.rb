# frozen_string_literal: true

class Contents::TransitionOperation < MainOperation
  attr_reader :content

  # @param params [Hash] :current_user, :id and :transition (:approve or :reject)
  # @return [void]
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
    @content_id = params[:id]
    @transition = params[:transition].to_sym
  end

  # Applies one supported review transition to the selected Content row.
  #
  # @return [void]
  def call
    step_load_content
    return if error?

    step_transition
  end

  private

  # Loads only Content owned by the authenticated user.
  #
  # @return [void]
  def step_load_content
    @content = Content.find_by(id: @content_id, user_id: current_user&.id)
    errors.add(:base, "Content không tồn tại hoặc không thuộc tài khoản của bạn") unless @content
  end

  # Runs the requested state transition and reports invalid lifecycle changes.
  #
  # @return [void]
  def step_transition
    case @transition
    when :approve then @content.approve!
    when :reject then @content.reject!
    else errors.add(:base, "Thao tác Content không hợp lệ")
    end
  rescue Content::InvalidTransitionError
    errors.add(:base, "Chỉ có thể approve hoặc reject Content đang ở trạng thái review")
  end
end
