class SocialConnections::ShowService < ApplicationService
  attr_reader :social_connection, :social_destinations

  # Initializes the selected profile detail service.
  #
  # @param social_connection_id [Integer] the selected profile
  # @return [SocialConnections::ShowService] the configured service
  def initialize(social_connection_id:)
    @social_connection_id = social_connection_id
    super()
  end

  # Loads the selected profile and its destinations.
  #
  # @return [Boolean] whether the profile was found
  def call
    return false unless step_load_social_connection

    step_load_social_destinations
    step_succeed!
  end

  private

  def step_load_social_connection
    @social_connection = SocialConnection.find_by(id: @social_connection_id)
    return step_fail!("Không tìm thấy kết nối này.") unless @social_connection

    true
  end

  def step_load_social_destinations
    @social_destinations = @social_connection.social_destinations.order(created_at: :desc).to_a
  end
end
