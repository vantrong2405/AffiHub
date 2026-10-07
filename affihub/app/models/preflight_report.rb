class PreflightReport < ApplicationRecord
  belongs_to :render_version, inverse_of: :preflight_reports

  scope :recent_first, proc { order(checked_at: :desc, id: :desc) }

  validates :checked_at, presence: true

  # Checks that the report covers this exact render version and destination and found it ready.
  #
  # @param render_version [RenderVersion] the immutable version under review
  # @param social_destination [SocialDestination] the destination to publish to
  # @return [Boolean] whether the report covers a ready destination for this version
  def ready_for?(render_version:, social_destination:)
    return false unless self.render_version_id == render_version.id
    return false unless checked_destination_ids.map(&:to_i).include?(social_destination.id)

    destination_results.dig(social_destination.id.to_s, "status") == "ready"
  end
end
