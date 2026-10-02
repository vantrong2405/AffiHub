# frozen_string_literal: true

class Contents::UpdateForm < MainForm
  attribute :body, :string

  validates :body, presence: true
end
