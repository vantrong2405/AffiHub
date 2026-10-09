require "rails_helper"

RSpec.describe "YouTube Publication consent", type: :system do
  it "queues a YouTube Publication after saving explicit privacy, disclosure, and upload terms consent" do
    video_project = create(:video_project)
    render_version = create(:render_version, video_project:, status: "ready")
    social_connection = create(
      :social_connection,
      provider: "youtube",
      external_user_id: "google-sub-1",
      name: "Google của Bếp Nhà"
    )
    social_destination = create(
      :social_destination,
      social_connection:,
      provider: "youtube",
      external_id: "channel-1",
      name: "Kênh Bếp Nhà"
    )
    publication = create(:publication, render_version:, social_destination:, caption: "Video bún bò")
    create(
      :preflight_report,
      render_version:,
      checked_destination_ids: [ social_destination.id ],
      destination_results: { social_destination.id.to_s => { "status" => "ready" } }
    )

    visit video_project_publication_path(video_project, publication)
    select "Không công khai", from: "Quyền riêng tư YouTube"
    select "Không", from: "Video này dành cho trẻ em"
    select "Có", from: "Video có nội dung tổng hợp hoặc chỉnh sửa bằng AI"
    check "youtube_upload_terms_confirmed"
    click_button "Lưu caption và xác nhận nội dung"
    expect(page).to have_content("Đã cập nhật caption.")
    click_button "Xác nhận đăng"
    expect(page).to have_content("Đã xác nhận yêu cầu đăng")

    expect(publication.reload.status).to eq("approved")
    expect(WorkflowRun.find_by!(workflowable: publication)).to have_attributes(status: "queued")
    expect(publication.consent_snapshot.slice(
      "upload_terms_confirmed",
      "youtube_account_id",
      "youtube_channel_id",
      "render_version_id",
      "publication_id",
      "privacy_status",
      "self_declared_made_for_kids",
      "contains_synthetic_media"
    )).to eq(
      "upload_terms_confirmed" => true,
      "youtube_account_id" => "google-sub-1",
      "youtube_channel_id" => "channel-1",
      "render_version_id" => render_version.id,
      "publication_id" => publication.id,
      "privacy_status" => "unlisted",
      "self_declared_made_for_kids" => false,
      "contains_synthetic_media" => true
    )
  end
end
