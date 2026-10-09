require "rails_helper"

RSpec.describe "Facebook connection screens", type: :system do
  it "returns the unconnected setup screen without showing the app secret" do
    visit new_social_connection_path(provider: "facebook")

    expect(page).to have_content("Kết nối Facebook")
    expect(page).to have_button("Tiếp tục với Facebook")
    expect(page).not_to have_content("affihub-test-secret")
  end

  it "starts Instagram connection through Facebook Login without exposing the app secret" do
    visit new_social_connection_path(provider: "instagram")

    expect(page).to have_content("Kết nối Instagram")
    expect(page).to have_content("Facebook Login for Business")
    expect(page).to have_button("Tiếp tục với Facebook")
    expect(page).not_to have_content("affihub-test-secret")
  end

  it "opens TikTok setup without exposing the client secret" do
    visit new_social_connection_path(provider: "tiktok")

    expect(page).to have_content("Kết nối TikTok")
    expect(page).to have_button("Tiếp tục với TikTok")
    expect(page).not_to have_content("tiktok-test-secret")
  end

  it "returns an empty state when there are no connected profiles" do
    visit social_connections_path

    expect(page).to have_content("Chưa có tài khoản kết nối")
  end
end
