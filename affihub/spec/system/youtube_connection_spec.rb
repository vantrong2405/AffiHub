require "rails_helper"

RSpec.describe "YouTube connection", type: :system do
  it "opens YouTube setup from the connected account list" do
    visit social_connections_path
    click_link "Kết nối YouTube"

    expect(page).to have_content("Kết nối YouTube")
    expect(page).to have_content("Sẵn sàng kết nối")
    expect(page).to have_button("Tiếp tục với Google")
  end

  it "returns the selected channel to the connected profile" do
    social_connection = create(
      :social_connection,
      provider: "youtube",
      external_user_id: "google-sub-1",
      name: "Google của Bếp Nhà"
    )
    stub_request(:get, "https://www.googleapis.com/youtube/v3/channels")
      .with(
        query: { "part" => "snippet", "mine" => "true", "maxResults" => "50" },
        headers: { "Authorization" => "Bearer user-access-token" }
      )
      .to_return(body: {
        items: [ { id: "channel-1", snippet: { title: "Kênh Bếp Nhà" } } ]
      }.to_json)

    visit social_connection_social_destinations_path(social_connection)
    check "Kênh Bếp Nhà"
    click_button "Thêm kênh đã chọn"

    expect(page).to have_content("Kênh Bếp Nhà")
    expect(page).not_to have_content("user-access-token")
  end
end
