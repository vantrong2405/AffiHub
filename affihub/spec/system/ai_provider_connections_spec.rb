require "rails_helper"

RSpec.describe "AI provider connections", type: :system do
  it "persists a selected Gemini model while the account remains pending verification" do
    ai_provider_connection = create(
      :ai_provider_connection,
      provider: "gemini",
      status: :pending_verification,
      selected_model: nil
    )

    visit ai_provider_connections_path
    click_link "Quản lý model"
    select "Gemini 3.5 Flash-Lite", from: "Model sử dụng"
    click_button "Lưu model"

    expect(
      ai_provider_connection.reload.attributes.slice("selected_model", "status")
    ).to eq(
      "selected_model" => "models/gemini-3.5-flash-lite",
      "status" => "pending_verification"
    )
  end
end
