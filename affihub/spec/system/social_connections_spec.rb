require "rails_helper"

RSpec.describe "Facebook connection screens", type: :system do
  it "returns the unconnected setup screen without showing the app secret" do
    visit new_social_connection_path(provider: "facebook")

    expect(page).to have_content("Kết nối Facebook")
    expect(page).to have_button("Tiếp tục với Facebook")
    expect(page).not_to have_content("affihub-test-secret")
  end

  it "returns an empty state when there are no connected profiles" do
    visit social_connections_path

    expect(page).to have_content("Chưa có tài khoản kết nối")
  end
end
