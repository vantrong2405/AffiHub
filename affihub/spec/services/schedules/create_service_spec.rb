require "rails_helper"

RSpec.describe Schedules::CreateService, type: :service do
  describe "#call" do
    let(:render_version) { create(:render_version) }
    let(:social_destination) { create(:social_destination) }
    let(:scheduled_at) { "2026-10-10T09:00:00+07:00" }
    let(:destination_settings) do
      {
        social_destination.id.to_s => {
          "caption" => "Video mới từ AffiHub",
          "consent_snapshot" => {}
        }
      }
    end
    let(:preflight_report) do
      create(
        :preflight_report,
        render_version:,
        checked_destination_ids: [ social_destination.id ],
        destination_results: { social_destination.id.to_s => { "status" => "ready" } }
      )
    end
    let(:service) do
      described_class.new(
        video_project_id: render_version.video_project_id,
        render_version_id: render_version.id,
        preflight_report_id: preflight_report.id,
        scheduled_at:,
        time_zone: "Asia/Ho_Chi_Minh",
        recurrence: "daily",
        destination_settings:
      )
    end

    it "returns a timezone-bound Schedule with one destination and a jittered occurrence" do
      expected_scheduled_at = ActiveSupport::TimeZone["Asia/Ho_Chi_Minh"].parse(scheduled_at)

      expect { service.call }.to change(Schedule, :count).by(1)
        .and change(ScheduleOccurrence, :count).by(1)

      expect(service.success?).to eq(true)
      expect(service.schedule.time_zone).to eq("Asia/Ho_Chi_Minh")
      expect(service.schedule.recurrence).to eq("daily")
      expect(service.schedule.next_occurrence_at).to eq(expected_scheduled_at)
      expect(service.schedule.schedule_destinations.sole.caption).to eq("Video mới từ AffiHub")
      expect(service.occurrence.scheduled_at).to eq(expected_scheduled_at)
      dispatch_window = expected_scheduled_at + 5.minutes..expected_scheduled_at + 30.minutes
      expect(dispatch_window.cover?(service.occurrence.dispatch_at)).to eq(true)
    end

    it "returns a queued Sheets row when the user saves a schedule" do
      create(
        :google_connection,
        integration: "sheets",
        spreadsheet_id: "spreadsheet-42",
        worksheet_title: "Nội dung"
      )
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      expect(service.call).to eq(true)

      expect(SheetSync.count).to eq(1)
      expect(SheetSync.sole).to have_attributes(
        render_version_id: render_version.id,
        social_destination_id: social_destination.id,
        status: "queued"
      )
      expect(Publication.where(render_version:).count).to eq(0)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.length).to eq(1)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.first.fetch(:job)).to eq(SheetSyncs::SyncJob)
    end

    it 'returns true and saves the schedule when the Drive side job cannot be enqueued' do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      google_connection = create(:google_connection, integration: "drive")
      render_version.update!(status: "ready")
      render_version.file.attach(io: StringIO.new("render bytes"), filename: "render.mp4", content_type: "video/mp4")
      allow(DriveExports::UploadJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError)
      expect(service.call).to eq(true)

      expect(service.schedule).to be_persisted
      expect(DriveExport.find_by!(render_version:, google_connection:).attributes.slice("status", "safe_error_code")).to eq(
        "status" => "failed",
        "safe_error_code" => "google_drive_job_enqueue_failed"
      )
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job.fetch(:job) }.count(DriveExports::UploadJob)).to eq(0)
    end

    it "returns the machine timezone when the user does not choose one" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TZ").and_return("Asia/Ho_Chi_Minh")
      service = described_class.new(
        video_project_id: render_version.video_project_id,
        render_version_id: render_version.id,
        preflight_report_id: preflight_report.id,
        scheduled_at:,
        recurrence: "once",
        destination_settings:
      )

      service.call

      expect(service.schedule.time_zone).to eq("Asia/Ho_Chi_Minh")
    end

    context "when the selected destination did not pass the chosen preflight report" do
      let(:preflight_report) do
        create(
          :preflight_report,
          render_version:,
          checked_destination_ids: [ social_destination.id ],
          destination_results: { social_destination.id.to_s => { "status" => "blocked" } }
        )
      end

      it "returns failure without creating a Schedule" do
        expect { service.call }.not_to change(Schedule, :count)

        expect(service.success?).to eq(false)
        expect(service.schedule).to eq(nil)
      end
    end

    context "when scheduling a TikTok destination" do
      let(:social_destination) do
        connection = create(:social_connection, provider: "tiktok", external_user_id: "creator-1")
        create(:social_destination, social_connection: connection, provider: "tiktok", external_id: "creator-1")
      end
      let(:destination_settings) do
        {
          social_destination.id.to_s => {
            "caption" => "Video TikTok",
            "consent_snapshot" => {
              "tiktok_social_connection_id" => social_destination.social_connection_id,
              "tiktok_creator_id" => social_destination.external_id,
              "tiktok_render_version_id" => render_version.id,
              "tiktok_publication_id" => 42,
              "privacy_level" => "SELF_ONLY",
              "tiktok_confirmed_at" => Time.current.iso8601
            }
          }
        }
      end

      it "returns the creator consent snapshot on the Schedule destination" do
        service.call

        snapshot = service.schedule.schedule_destinations.sole.consent_snapshot

        expect(service.success?).to eq(true)
        expect(snapshot.fetch("tiktok_social_connection_id")).to eq(social_destination.social_connection_id)
        expect(snapshot.fetch("tiktok_creator_id")).to eq(social_destination.external_id)
        expect(snapshot.fetch("privacy_level")).to eq("SELF_ONLY")
        expect(snapshot.fetch("tiktok_schedule_id")).to eq(service.schedule.id)
      end

      it "returns failure without confirmed creator consent" do
        destination_settings[social_destination.id.to_s]["consent_snapshot"].delete("tiktok_confirmed_at")

        expect { service.call }.not_to change(Schedule, :count)

        expect(service.success?).to eq(false)
        expect(service.errors.full_messages.to_sentence).to eq("Cần lưu và xác nhận consent TikTok trước khi lập lịch.")
      end
    end

    context "when scheduling a YouTube destination" do
      let(:social_destination) do
        connection = create(:social_connection, provider: "youtube", external_user_id: "account-1")
        create(:social_destination, social_connection: connection, provider: "youtube", external_id: "channel-1")
      end
      let(:destination_settings) do
        { social_destination.id.to_s => { "caption" => "Video YouTube", "consent_snapshot" => {} } }
      end

      it "returns failure when upload terms and privacy choice were not saved" do
        expect { service.call }.not_to change(Schedule, :count)

        expect(service.success?).to eq(false)
        expect(service.errors.full_messages.to_sentence).to eq("Cần lưu thông tin tải YouTube trước khi lập lịch.")
      end
    end
  end
end
