# frozen_string_literal: true

module Dashboard
  class BuildStatusOperation < MainOperation
    attr_reader :ai_connection, :affiliate_connection, :social_connection, :recent_publications

    # Initializes an operation without a validation form.
    #
    # @param params [Hash] current-user context
    # @return [void]
    def initialize(params:)
      super
      @errors = ActiveModel::Errors.new(self)
    end

    # Loads the signed-in user's provider connections and latest publications.
    #
    # @return [void]
    def call
      step_load_connections
      step_load_recent_publications
    end

    private

    # Reads each provider connection through the current user's association.
    #
    # @return [void]
    def step_load_connections
      @ai_connection = current_user.ai_connection
      @affiliate_connection = current_user.affiliate_connection
      @social_connection = current_user.social_connection
    end

    # Loads at most ten newest publications belonging to the current user.
    #
    # @return [void]
    def step_load_recent_publications
      @recent_publications = Publication
        .joins(social_destination: :social_connection)
        .where(social_connections: { user_id: current_user.id })
        .includes(:content, :social_destination)
        .order(created_at: :desc, id: :desc)
        .limit(10)
    end
  end
end
