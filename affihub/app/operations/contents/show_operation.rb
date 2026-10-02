# frozen_string_literal: true

class Contents::ShowOperation < MainOperation
  attr_reader :content

  # @param params [Hash] :current_user and :id
  # @return [void]
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
    @content_id = params[:id]
  end

  # Loads a Content row only when it belongs to the current user.
  #
  # @return [void]
  def call
    @content = Content.includes(:product).find_by(id: @content_id, user_id: current_user&.id)
  end
end
