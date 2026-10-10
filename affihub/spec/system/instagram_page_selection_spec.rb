require "rails_helper"

RSpec.describe "Instagram Business destination selection", type: :system do
  let(:social_connection) do
    create(
      :social_connection,
      provider: "instagram",
      external_user_id: "facebook-user-1",
      name: "Facebook của Bếp Nhà"
    )
  end
  let(:meta_client) { double("Meta::Client") }
  let(:pages) do
    [
      {
        "id" => "page-1",
        "name" => "Page Bếp Nhà",
        "access_token" => "page-token-secret",
        "tasks" => [ "CREATE_CONTENT" ],
        "instagram_business_account" => { "id" => "ig-business-1", "account_type" => "BUSINESS" }
      },
      {
        "id" => "page-creator",
        "name" => "Page Creator",
        "access_token" => "creator-page-token",
        "tasks" => [ "CREATE_CONTENT" ],
        "instagram_business_account" => { "id" => "ig-creator-1", "account_type" => "CREATOR" }
      }
    ]
  end

  before do
    social_connection
    allow(Meta::Client).to receive(:new).with(provider: "instagram").and_return(meta_client)
    allow(meta_client).to receive(:pages).with(access_token: "user-access-token").and_return(pages)
  end

  it "shows the linked Business account and prevents selecting a Creator account" do
    visit social_connection_social_destinations_path(social_connection)

    expect(page).to have_content("Instagram Business account ID ig-business-1")
    expect(page).to have_content("Page ID page-1")
    expect(page).to have_field("Page Creator", disabled: true)
    expect(page).not_to have_content("page-token-secret")

    check "Page Bếp Nhà"
    click_button "Thêm tài khoản Instagram Business đã chọn"

    expect(page).to have_content("Instagram Business account ID ig-business-1")
    expect(page).to have_content("Page ID page-1")
    expect(page).not_to have_content("page-token-secret")
  end
end
