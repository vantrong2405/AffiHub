require "rails_helper"

RSpec.describe "Render version editor", type: :system do
  it "submits an edit for the selected source" do
    video_project = create(:video_project)
    source_asset = create(
      :source_asset,
      video_project:,
      status: "ready",
      media_metadata: { "duration_seconds" => 6.0, "width" => 32, "height" => 32, "has_audio" => true }
    )
    source_asset.file.attach(
      io: StringIO.new(File.binread(Rails.root.join("spec/fixtures/files/local_source.mp4"))),
      filename: "local-source.mp4",
      content_type: "video/mp4"
    )

    visit new_video_project_render_version_path(video_project, source_asset_id: source_asset.id)
    within("#timeline-editor") do
      fill_in "Bắt đầu (giây)", with: "0"
      fill_in "Kết thúc (giây)", with: "2"
      select "2×", from: "Tốc độ"
    end
    click_button "Tạo bản render"

    expect(page).to have_text("Đang chờ render")
    expect(RenderVersion.last.source_asset).to eq(source_asset)
  end
end
