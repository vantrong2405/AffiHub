# frozen_string_literal: true

# Read-only: loads the current_user's AIConnection without the controller querying the model
# directly. See affihub/CLAUDE.md HTML-controller conventions.
class AIConnections::ShowOperation < MainOperation
  # @return [AIConnection, nil] the current_user's AIConnection, once #call has run
  attr_reader :ai_connection

  # @param params [Hash] :current_user (required)
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
  end

  # @return [void]
  def call
    @ai_connection = current_user.ai_connection
  end
end
