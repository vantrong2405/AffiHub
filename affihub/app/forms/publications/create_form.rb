# frozen_string_literal: true

class Publications::CreateForm < MainForm
  attr_reader :current_user, :content, :social_destination
  attribute :content_id, :integer
  attribute :social_destination_id, :integer

  validates :content_id, :social_destination_id, presence: true
  validate :validate_owned_approved_content
  validate :validate_owned_destination

  # @param params [Hash] :current_user, :content_id, and :social_destination_id
  # @return [void]
  def initialize(params = {})
    @current_user = params[:current_user]
    super(params.slice(:content_id, :social_destination_id))
  end

  # Resolves the supplied Content and SocialDestination within the authenticated user's scope.
  #
  # @return [void]
  def validate_owned_approved_content
    @content = current_user&.contents&.find_by(id: content_id)
    errors.add(:content_id, "must belong to you and be approved") unless @content&.status_approved?
  end

  # Resolves the supplied Page destination within the authenticated user's scope.
  #
  # @return [void]
  def validate_owned_destination
    @social_destination = SocialDestination.joins(:social_connection).find_by(
      id: social_destination_id,
      social_connections: { user_id: current_user&.id }
    )
    errors.add(:social_destination_id, "must be a Page connected to your account") unless @social_destination
  end
end
