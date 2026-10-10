require "rails_helper"

RSpec.describe "Schedule management", type: :system do
  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "creates a Schedule with the selected local timezone and recurrence" do
    video_project = create(:video_project)
    render_version = create(:render_version, video_project:, status: "ready")
    social_destination = create(:social_destination, name: "Facebook Bếp Nhà")
    preflight_report = create(
      :preflight_report,
      render_version:,
      checked_destination_ids: [ social_destination.id ],
      destination_results: { social_destination.id.to_s => { "status" => "ready" } }
    )
    scheduled_at = 2.days.from_now.in_time_zone("Asia/Ho_Chi_Minh").strftime("%Y-%m-%dT%H:%M")

    visit new_video_project_schedule_path(video_project, preflight_report_id: preflight_report.id)
    scheduled_at_input = find("input[name='schedule[scheduled_at]']")
    scheduled_at_input.set(Time.zone.parse(scheduled_at))
    expect(scheduled_at_input.value).to eq(scheduled_at)
    select "Asia/Ho_Chi_Minh", from: "Timezone"
    select "Hằng ngày", from: "Lặp lại"
    check "Facebook Bếp Nhà"
    fill_in "Caption cho Facebook Bếp Nhà", with: "Bản tin tuần này"
    click_button "Lên lịch video"

    expect(page).to have_content("Đã tạo lịch đăng")
    schedule = Schedule.order(:id).last

    expect(schedule.time_zone).to eq("Asia/Ho_Chi_Minh")
    expect(schedule.recurrence).to eq("daily")
    expect(schedule.next_occurrence_at.in_time_zone(schedule.time_zone).strftime("%Y-%m-%dT%H:%M")).to eq(scheduled_at)
    expect(schedule.schedule_destinations.sole.caption).to eq("Bản tin tuần này")
    expect(page).to have_content(I18n.l(schedule.next_occurrence_at.in_time_zone(schedule.time_zone), format: :long))
  end

  it "shows quota and a missed occurrence while pause and resume never enqueue catch-up publishing" do
    video_project = create(:video_project)
    render_version = create(:render_version, video_project:)
    schedule = create(:schedule, render_version:, recurrence: "daily")
    social_destination = create(:social_destination, name: "Facebook Bếp Nhà")
    create(:schedule_destination, schedule:, social_destination:)
    missed_occurrence = create(:schedule_occurrence, schedule:, status: "missed")
    create_list(:publication_quota_reservation, 4, social_destination:, reserved_at: 30.minutes.ago)

    visit video_project_schedule_path(video_project, schedule)

    expect(page).to have_content("Bị lỡ")
    expect(page).to have_content("4 / 5")
    expect(page).to have_content("Facebook Bếp Nhà")
    click_button "Tạm dừng lịch"

    expect(schedule.reload.status).to eq("paused")
    click_button "Tiếp tục lịch"

    expect(schedule.reload.status).to eq("active")
    expect(missed_occurrence.reload.status).to eq("missed")
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.count).to eq(0)
  end
end
