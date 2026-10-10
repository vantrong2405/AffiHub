class SocialConnections::IndexService < ApplicationService
  attr_reader :social_connections

  # Initializes the connected profile list service.
  #
  # @return [SocialConnections::IndexService] the configured service
  def initialize
    super()
  end

  # Loads profiles from newest to oldest.
  #
  # @return [Boolean] whether the profiles were loaded
  def call
    step_load_social_connections
    step_succeed!
  end

  private

  def step_load_social_connections
    @social_connections = SocialConnection.order(created_at: :desc).to_a
  end
end
