# frozen_string_literal: true

class SocialConnections::ShowOperation < MainOperation
  attr_reader :social_connection

  # @param params [Hash] :current_user
  # @return [void]
  def initialize(params:)
    super(params:)
    @errors = ActiveModel::Errors.new(self)
  end

  # Returns the Facebook connection belonging to the current user.
  #
  # @return [void]
  def call
    @social_connection = current_user&.social_connection
  end
end
