require "rails_helper"

RSpec.describe "Publication review", type: :system do
  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "queues a publish only after the operator confirms a ready draft" do
    video_project = create(:video_project)
    render_version = create(:render_version, video_project:, status: "ready")
    social_destination = create(:social_destination, name: "Page Bếp Nhà")
    publication = create(:publication, render_version:, social_destination:, caption: "Video món ăn")
    preflight_report = create(
      :preflight_report,
      render_version:,
      checked_destination_ids: [ social_destination.id ],
      destination_results: { social_destination.id.to_s => { "status" => "ready" } }
    )
    visit video_project_publication_path(video_project, publication)
    click_button "Xác nhận đăng"

    expect(page).to have_content("Đã xác nhận yêu cầu đăng")
    expect(publication.reload.status).to eq("approved")
    expect(WorkflowRun.find_by!(workflowable: publication)).to have_attributes(status: "queued")
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.size).to eq(1)
  end

  it "requires evidence and risk confirmation before marking an unknown post as not occurred" do
    video_project = create(:video_project)
    render_version = create(:render_version, video_project:)
    publication = create(:publication, render_version:, status: "outcome_unknown")
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
    select "Bài chưa đăng", from: "Quyết định"
    fill_in "Bằng chứng kiểm tra", with: "Đã kiểm tra Page và không thấy bài"
    check "Tôi xác nhận đã kiểm tra kỹ để tránh đăng trùng"
    click_button "Ghi nhận quyết định"

    expect(page).to have_content("Đã ghi nhận kết quả kiểm tra")
    expect(publication.reload.status).to eq("manual_outcome_not_occurred")
    expect(workflow_run.reload.status).to eq("queued")
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.size).to eq(1)
  end
end
