class PublicationQuotaReservation < ApplicationRecord
  belongs_to :publication, inverse_of: :quota_reservation
  belongs_to :social_destination, inverse_of: :publication_quota_reservations

  validates :publication_id, uniqueness: true
  validates :reserved_at, presence: true
  validate :publication_destination_matches

  private

  def publication_destination_matches
    return if publication.blank? || social_destination_id == publication.social_destination_id

    errors.add(:social_destination_id, :invalid)
  end
end
