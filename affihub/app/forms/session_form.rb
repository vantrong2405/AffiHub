# frozen_string_literal: true

class SessionForm < MainForm
  attribute :email, :string
  attribute :password, :string

  validates :email, presence: true
  validates :password, presence: true
end
