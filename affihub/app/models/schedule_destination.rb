class ScheduleDestination < ApplicationRecord
  belongs_to :schedule, inverse_of: :schedule_destinations
  belongs_to :social_destination, inverse_of: :schedule_destinations

  validates :social_destination_id, uniqueness: { scope: :schedule_id }
  validate :destination_provider_matches_consent_snapshot

  private

  def destination_provider_matches_consent_snapshot
    return if social_destination.blank?

    snapshot = consent_snapshot.to_h.stringify_keys
    return if social_destination.provider == "tiktok" &&
      snapshot["tiktok_social_connection_id"].to_s == social_destination.social_connection_id.to_s &&
      snapshot["tiktok_creator_id"].to_s == social_destination.external_id.to_s
    return if social_destination.provider != "tiktok"

    errors.add(:consent_snapshot, :invalid)
  end
end
