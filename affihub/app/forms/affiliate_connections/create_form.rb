# frozen_string_literal: true

class AffiliateConnections::CreateForm < MainForm
  attribute :api_key, :string

  validates :api_key, presence: true
end
