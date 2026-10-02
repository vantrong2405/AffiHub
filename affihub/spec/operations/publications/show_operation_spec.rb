# frozen_string_literal: true

require "rails_helper"

RSpec.describe Publications::ShowOperation do
  it "loads an owned Publication and hides a Publication belonging to another user" do
    user = create(:user)
    own = create(:publication, content: create(:content, user: user))
    foreign = create(:publication)

    expect(described_class.call(params: { current_user: user, id: own.id }).publication).to eq(own)
    expect(described_class.call(params: { current_user: user, id: foreign.id }).publication).to be_nil
  end
end
