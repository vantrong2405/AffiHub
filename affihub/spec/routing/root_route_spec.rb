# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Root route", type: :routing do
  it "routes GET / to DashboardController#show" do
    expect(get: "/").to route_to("dashboard#show")
  end
end
