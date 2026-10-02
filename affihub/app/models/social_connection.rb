# frozen_string_literal: true

class SocialConnection < ApplicationRecord
  belongs_to :user
  has_many :social_destinations, dependent: :destroy

  encrypts :access_token

  validates :provider, uniqueness: { scope: :user_id }
end
