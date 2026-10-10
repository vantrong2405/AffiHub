require "rails_helper"

RSpec.describe "TikTok Publication consent", type: :system do
  let(:video_project) { create(:video_project) }
  let(:render_version) { create(:render_version, video_project:, status: "ready") }
  let(:social_connection) do
    create(
      :social_connection,
      provider: "tiktok",
      external_user_id: "creator-1",
      name: "TikTok của Bếp Nhà"
    )
  end
  let(:social_destination) do
    create(
      :social_destination,
      social_connection:,
      provider: "tiktok",
      external_id: "creator-1",
      name: "Bếp Nhà"
    )
  end
  let(:publication) { create(:publication, render_version:, social_destination:, caption: "Video bún bò") }
  let(:tiktok_client) { double("TikTok::Client") }

  before do
    social_destination
    token_service = double("TikTok access token service", call: true, access_token: "creator-access-token")
    allow(SocialConnections::TikTok::AccessTokenService).to receive(:new)
      .with(social_destination_id: social_destination.id)
      .and_return(token_service)
    allow(TikTok::Client).to receive(:new).and_return(tiktok_client)
    allow(tiktok_client).to receive(:creator_info).with(access_token: "creator-access-token").and_return(
      "data" => {
        "privacy_level_options" => [ "SELF_ONLY", "PUBLIC_TO_EVERYONE" ],
        "comment_disabled" => false,
        "duet_disabled" => false,
        "stitch_disabled" => false
      },
      "error" => { "code" => "ok" }
    )
  end

  it "saves explicit privacy and AI disclosure with both commercial content toggles off" do
    create(
      :preflight_report,
      render_version:,
      checked_destination_ids: [ social_destination.id ],
      destination_results: { social_destination.id.to_s => { "status" => "ready" } }
    )
    visit video_project_publication_path(video_project, publication)
    select "Chỉ mình tôi", from: "Quyền riêng tư TikTok"
    select "Có", from: "Video có nội dung do AI tạo hoặc chỉnh sửa"
    check "Tôi xác nhận tài khoản TikTok đang ở chế độ riêng tư"
    check "Tôi xác nhận có quyền sử dụng nhạc trong video"
    click_button "Lưu caption và xác nhận TikTok"

    expect(page).to have_select("Quyền riêng tư TikTok", selected: "Chỉ mình tôi")
    expect(page).to have_select("Video có nội dung do AI tạo hoặc chỉnh sửa", selected: "Có")
    expect(page).not_to have_checked_field("brand_organic_toggle")
    expect(page).not_to have_checked_field("brand_content_toggle")

    click_button "Xác nhận đăng"

    expect(page).to have_content("Đã xác nhận yêu cầu đăng.")
    expect(page).to have_content("Đang chờ xử lý")
  end

  it "locks TikTok interactions disabled by the creator settings" do
    allow(tiktok_client).to receive(:creator_info).with(access_token: "creator-access-token").and_return(
      "data" => {
        "privacy_level_options" => [ "SELF_ONLY" ],
        "comment_disabled" => true,
        "duet_disabled" => false,
        "stitch_disabled" => true
      },
      "error" => { "code" => "ok" }
    )

    visit video_project_publication_path(video_project, publication)

    expect(page).to have_field("allow_comment", disabled: true)
    expect(page).to have_field("allow_duet", disabled: false)
    expect(page).to have_field("allow_stitch", disabled: true)
  end

  it "shows that TikTok does not provide a remaining-post counter" do
    visit video_project_publication_path(video_project, publication)

    expect(page).to have_content("Chưa thể kiểm tra số bài còn lại")
  end

  it "does not say the creator disabled interactions when settings are unavailable" do
    token_service = double("TikTok access token service", call: false, access_token: nil)
    allow(SocialConnections::TikTok::AccessTokenService).to receive(:new)
      .with(social_destination_id: social_destination.id)
      .and_return(token_service)

    visit video_project_publication_path(video_project, publication)

    expect(page).to have_content("Không thể kiểm tra cài đặt tương tác")
    expect(page).to have_content("Không lấy được trạng thái giới hạn từ TikTok")
    expect(page).not_to have_content("TikTok không cung cấp bộ đếm quota")
    expect(page).not_to have_content("Creator đã tắt lựa chọn này")
  end

  it "shows a TikTok-specific reconciliation form for an unknown publish outcome" do
    publication.update!(status: "outcome_unknown")
    workflow_run = create(
      :workflow_run,
      workflowable: publication,
      operation: "publication_publish",
      stage: "publish",
      status: "outcome_unknown"
    )
    create(
      :outbound_attempt,
      workflow_run:,
      status: "outcome_unknown",
      sender_stopped_at: 2.minutes.ago,
      request_timeout_at: 1.minute.ago
    )

    visit video_project_publication_path(video_project, publication)

    expect(page).to have_content("Hãy kiểm tra bài trên TikTok")
    expect(page).to have_content("Đối soát kết quả đăng")
    expect(page).to have_field("Bằng chứng kiểm tra")
  end
end
