require "rails_helper"

RSpec.describe "Source ingestion", type: :system do
  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "queues a URL import after the user confirms the rights notice" do
    video_project = create(:video_project)
    allow(Resolv).to receive(:getaddresses).with("youtu.be").and_return([ "142.250.72.238" ])

    visit new_video_project_source_asset_path(video_project)
    fill_in "URL video", with: "https://youtu.be/video-123"
    check "Tôi có quyền sử dụng video này và đã kiểm tra điều khoản của nguồn."
    click_button "Thử tải video"

    expect(page).to have_content("Đã nhận yêu cầu tải video")
    expect(page).to have_content("https://youtu.be/video-123")
  end

  it "shows the file import fallback after a source download fails" do
    video_project = create(:video_project)
    source_asset = create(
      :source_asset,
      video_project:,
      source_type: "url_download",
      source_url: "https://youtu.be/video-123",
      status: "failed",
      download_error: "AffiHub không thể tải video tự động. Hãy nhập file MP4 hoặc MOV."
    )

    visit video_project_source_asset_path(video_project, source_asset)
    expect(page).to have_content("Hãy nhập file MP4 hoặc MOV")
    click_link "Thêm nguồn video"
    attach_file "File video", Rails.root.join("spec/fixtures/files/local_source.mp4")
    click_button "Tải file và kiểm tra"

    expect(page).to have_content("File đã được nhận")
    expect(page).to have_content("local_source.mp4")
  end

  it "explains when the local rolling download limit delays a source" do
    video_project = create(:video_project)
    source_asset = create(
      :source_asset,
      video_project:,
      source_type: "url_download",
      source_url: "https://youtu.be/video-123",
      status: "waiting_for_download_slot",
      download_error_code: "download_slot_limit",
      download_error: "Đã chạm giới hạn lượt tải. AffiHub sẽ thử lại khi có lượt trống."
    )

    visit video_project_source_asset_path(video_project, source_asset)

    expect(page).to have_content("Chờ lượt tải")
    expect(page).to have_content("10 lượt tải trong 60 phút")
  end
end
