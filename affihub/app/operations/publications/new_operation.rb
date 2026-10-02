# frozen_string_literal: true

class Publications::NewOperation < MainOperation
  attr_reader :contents, :destinations

  # @param params [Hash] :current_user
  # @return [void]
  def initialize(params:)
    super(params:)
    @errors = ActiveModel::Errors.new(self)
  end

  # Lists approved owned Content and Facebook Page destinations for the new form.
  #
  # @return [void]
  def call
    @contents = current_user.contents.status_approved.includes(:product).order(created_at: :desc)
    @destinations = SocialDestination.joins(:social_connection)
      .where(social_connections: { user_id: current_user.id, provider: "facebook" })
      .order(:name)
  end
end
