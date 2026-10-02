# frozen_string_literal: true

class SocialDestination < ApplicationRecord
  belongs_to :social_connection
  has_many :publications, dependent: :restrict_with_exception

  encrypts :page_access_token

  validates :page_id, uniqueness: { scope: :social_connection_id }
end
