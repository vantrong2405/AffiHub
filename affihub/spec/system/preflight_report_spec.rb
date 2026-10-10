require "rails_helper"

RSpec.describe "Preflight report", type: :system do
  let(:video_project) { create(:video_project) }
  let(:render_version) { create(:render_version, video_project:, status: "ready", metadata: { "duration_seconds" => 2.0 }) }
  let(:blocked_destination) do
    create(:social_destination, name: "Page Bếp Nhà", social_connection: create(:social_connection, provider: "facebook"))
  end
  let(:ready_destination) do
    create(:social_destination, name: "Kênh Bếp Nhà", social_connection: create(:social_connection, provider: "youtube"), provider: "youtube")
  end
  let(:preflight_report) do
    create(
      :preflight_report,
      render_version:,
      checked_destination_ids: [ blocked_destination.id, ready_destination.id ],
      destination_results: {
        "project" => {
          "status" => "ready",
          "checks" => {
            "source" => { "status" => "passed", "subject" => "SourceAsset", "reason" => "Source file sẵn sàng.", "action" => "Không cần khắc phục." },
            "render" => { "status" => "passed", "subject" => "RenderVersion", "reason" => "Render đạt profile.", "action" => "Không cần khắc phục." },
            "worker" => { "status" => "passed", "subject" => "Solid Queue worker", "reason" => "Worker đang chạy.", "action" => "Không cần khắc phục." },
            "ai_estimate" => { "status" => "warning", "subject" => "AI estimate", "reason" => "Estimate chỉ mang tính tham khảo.", "action" => "Xem lại estimate trước tác vụ tính phí." },
            "paid_ai" => { "status" => "blocked", "subject" => "MoneyPrinterTurbo", "reason" => "Recovery chưa được xác minh.", "action" => "Chạy smoke test restart/reconcile." },
            "google_drive" => { "status" => "not_configured", "subject" => "Google Drive", "reason" => "Integration chưa được kết nối.", "action" => "Kết nối nếu muốn dùng đồng bộ Drive." },
            "google_sheets" => { "status" => "not_configured", "subject" => "Google Sheets", "reason" => "Integration chưa được kết nối.", "action" => "Kết nối nếu muốn dùng đồng bộ Sheets." },
            "publish_readiness" => { "status" => "passed", "subject" => video_project.name, "reason" => "Đã chọn 2 destination.", "action" => "Xem readiness trong từng destination." }
          }
        },
        blocked_destination.id.to_s => {
          "status" => "blocked",
          "production_gates" => [
            {
              "key" => "meta_app_review",
              "status" => "not_verified",
              "subject" => "Meta App Review",
              "reason" => "Preflight không đọc trạng thái App Review hoặc access tier của Meta App.",
              "action" => "Kiểm tra Meta App Dashboard trước khi phát hành."
            }
          ],
          "checks" => {
            "connector" => { "status" => "blocked", "subject" => blocked_destination.name, "reason" => "Token destination đã hết hạn.", "action" => "Kết nối lại account/Page rồi chạy preflight." },
            "media_transfer" => { "status" => "passed", "subject" => blocked_destination.name, "reason" => "Upload local đã cấu hình.", "action" => "Không cần khắc phục." },
            "permissions" => { "status" => "unavailable", "subject" => blocked_destination.name, "reason" => "Connection chưa sẵn sàng.", "action" => "Kết nối lại Facebook rồi kiểm tra quyền Page." }
          }
        },
        ready_destination.id.to_s => {
          "status" => "ready",
          "production_gates" => [
            {
              "key" => "youtube_compliance_audit",
              "status" => "not_verified",
              "subject" => "YouTube compliance audit",
              "reason" => "Audit chỉ cần khi xin quota cao hơn mức mặc định.",
              "action" => "Kiểm tra quy trình audit nếu cần tăng quota."
            }
          ],
          "checks" => {
            "connector" => { "status" => "passed", "subject" => ready_destination.name, "reason" => "Kết nối và quyền đang sẵn sàng.", "action" => "Không cần khắc phục." },
            "media_transfer" => { "status" => "passed", "subject" => ready_destination.name, "reason" => "Upload local đã cấu hình.", "action" => "Không cần khắc phục." },
            "quota" => { "status" => "passed", "subject" => ready_destination.name, "reason" => "Quota còn khả dụng.", "action" => "Không cần khắc phục." }
          }
        }
      }
    )
  end
  let(:frame_service) do
    instance_double(
      RenderVersions::CompareFramesService,
      call: true,
      success?: true,
      frames: []
    )
  end

  before do
    allow(RenderVersions::CompareFramesService).to receive(:new).and_return(frame_service)
  end

  it "returns independent blocked, unconfigured, and ready destination checks" do
    visit video_project_preflight_report_path(video_project, preflight_report)

    expect(page).to have_content("Google Drive")
    expect(page).to have_content("Chưa cấu hình")
    expect(page).to have_content("Token destination đã hết hạn.")
    expect(page).to have_content("Kết nối và quyền đang sẵn sàng.")
  end

  it 'returns only the selected destination and its production gate after filtering' do
    visit video_project_preflight_report_path(video_project, preflight_report)
    select "Page Bếp Nhà · Facebook", from: "Destination"
    click_button "Lọc"

    expect(page).to have_css("#destination-#{blocked_destination.id}", count: 1)
    expect(page).to have_no_css("#destination-#{ready_destination.id}")
    expect(page).to have_content("Google Drive")
    expect(page).to have_content("Meta App Review")
    expect(page).to have_no_content("YouTube compliance audit")
  end

  it 'returns the draft form for the exact report without creating a publication' do
    visit video_project_preflight_report_path(video_project, preflight_report)
    click_link "Tạo bản nháp (đạt kỹ thuật)"

    expect(page).to have_current_path(new_video_project_publication_path(video_project, preflight_report_id: preflight_report.id))
    expect(page).to have_content("Tạo bản đăng")
    expect(Publication.count).to eq(0)
  end

  it "returns a saved report scoped to the destination selected on the render page" do
    source_metadata = {
      "duration_seconds" => 2.0,
      "width" => 1080,
      "height" => 1920,
      "frame_rate" => 30,
      "video_codec" => "h264",
      "audio_codec" => "aac",
      "has_audio" => true
    }
    source_asset = create(:source_asset, video_project:, status: "ready", media_metadata: source_metadata)
    render_version = create(
      :render_version,
      video_project:,
      source_asset:,
      status: "ready",
      edit_config: {
        "schema_version" => 1,
        "segments" => [ { "start_seconds" => 0.0, "end_seconds" => 2.0, "speed" => 1.0, "audio_mode" => "keep", "audio_volume" => 1.0 } ],
        "canvas" => { "mode" => "fit", "background" => { "type" => "blur" } },
        "filters" => { "brightness" => 0.0, "contrast" => 1.0 },
        "overlays" => [],
        "delogo_regions" => []
      },
      metadata: source_metadata
    )
    media_bytes = File.binread(Rails.root.join("spec/fixtures/files/edit_source.mp4"))
    source_asset.file.attach(io: StringIO.new(media_bytes), filename: "source.mp4", content_type: "video/mp4")
    render_version.file.attach(io: StringIO.new(media_bytes), filename: "render.mp4", content_type: "video/mp4")
    youtube_scopes = Rails.application.config_for(:youtube).deep_symbolize_keys.dig(:oauth, :required_publish_scopes)
    social_connection = create(:social_connection, provider: "youtube", scopes: youtube_scopes)
    social_destination = create(
      :social_destination,
      social_connection:,
      provider: "youtube",
      external_id: "channel-preflight-review",
      name: "Kênh Bếp Nhà"
    )

    visit video_project_render_version_path(video_project, render_version)
    check "Kênh Bếp Nhà"
    click_button "Kiểm tra toàn bộ"

    expect(page).to have_content("Kết quả Kiểm tra toàn bộ")
    expect(page).to have_content("Kết quả theo destination")
    expect(page).to have_content("Kênh Bếp Nhà")
    expect(Publication.count).to eq(0)
  end
end
