# frozen_string_literal: true

class Publications::ShowOperation < MainOperation
  attr_reader :publication

  # @param params [Hash] :current_user and :id
  # @return [void]
  def initialize(params:)
    super(params:)
    @errors = ActiveModel::Errors.new(self)
    @publication_id = params[:id]
  end

  # Loads one Publication through the current user's Content ownership.
  #
  # @return [void]
  def call
    @publication = Publication.includes(:content, :social_destination).joins(:content)
      .find_by(id: @publication_id, contents: { user_id: current_user&.id })
  end
end
