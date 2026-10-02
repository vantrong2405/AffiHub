# frozen_string_literal: true

class AffiliateConnection < ApplicationRecord
  belongs_to :user

  encrypts :api_key

  validates :provider, presence: true
end
