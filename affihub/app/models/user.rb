# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password

  has_one :ai_connection, dependent: :destroy
  has_one :affiliate_connection, dependent: :destroy
  has_one :social_connection, dependent: :destroy
  has_many :products, dependent: :destroy
  has_many :contents, dependent: :destroy

  validates :email, presence: true, uniqueness: true
end
