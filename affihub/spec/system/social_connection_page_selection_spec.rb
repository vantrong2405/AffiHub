require "rails_helper"

RSpec.describe "Facebook Page selection", type: :system do
  let(:social_connection) { create(:social_connection) }

  before do
    stub_request(:get, "https://graph.facebook.com/v26.0/me/accounts")
      .with(query: hash_including("access_token" => "user-access-token"))
      .to_return(body: { data: [
        { id: "page-1", name: "Page Một", access_token: "page-token-1", tasks: [ "PROFILE_PLUS_CREATE_CONTENT" ] },
        { id: "page-2", name: "Page Hai", access_token: "page-token-2", tasks: [ "PROFILE_PLUS_CREATE_CONTENT" ] }
      ] }.to_json)
  end

  it "returns the selected Page on the connected profile" do
    visit social_connection_social_destinations_path(social_connection)
    check "Page Hai"
    click_button "Thêm Page đã chọn"

    expect(page).to have_content("Page Hai")
    expect(page).not_to have_content("page-token-2")
  end

  it "returns a warning and disables a Page without content permission" do
    stub_request(:get, "https://graph.facebook.com/v26.0/me/accounts")
      .with(query: hash_including("access_token" => "user-access-token"))
      .to_return(body: { data: [
        { id: "page-2", name: "Page Chỉ xem", access_token: "page-token-2", tasks: [ "PROFILE_PLUS_ANALYZE" ] }
      ] }.to_json)
    visit social_connection_social_destinations_path(social_connection)

    expect(page).to have_content("Page chưa cấp quyền tạo nội dung")
    expect(page).to have_field("Page Chỉ xem", disabled: true)
  end
end
