require "rails_helper"

RSpec.describe Schedules::ProcessOccurrenceService, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  describe "#call" do
    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    let(:schedule) { create(:schedule) }
    let(:scheduled_at) { 10.minutes.ago }
    let(:occurrence) do
      create(
        :schedule_occurrence,
        schedule:,
        occurrence_key: scheduled_at.utc.iso8601(6),
        scheduled_at:,
        dispatch_at: scheduled_at + 5.minutes
      )
    end
    let(:service) { described_class.new(schedule_occurrence_id: occurrence.id) }

    it "returns false without processing an occurrence before its jitter time" do
      travel_to(scheduled_at + 4.minutes) do
        expect(service.call).to eq(false)
      end

      expect(occurrence.reload.status).to eq("scheduled")
      expect(occurrence.publications.to_a).to eq([])
    end

    it "returns success after marking a late occurrence missed without publishing" do
      occurrence
      travel_to(scheduled_at + 31.minutes) do
        expect(service.call).to eq(true)
      end

      expect(occurrence.reload.status).to eq("missed")
      expect(occurrence.publications.to_a).to eq([])
      expect(Publications::PublishJob).not_to have_been_enqueued
      expect(schedule.reload.status).to eq("completed")
    end

    it "returns success after skipping an occurrence whose Schedule is paused" do
      schedule.update!(status: "paused")
      occurrence

      expect(PreflightReports::CreateService).not_to receive(:new)

      expect(service.call).to eq(true)

      expect(occurrence.reload.status).to eq("skipped")
      expect(occurrence.publications.to_a).to eq([])
      expect(Publications::PublishJob).not_to have_been_enqueued
    end

    context "when a recurring Schedule is paused at an occurrence time" do
      let(:schedule) { create(:schedule, recurrence: "daily", status: "paused") }

      it "returns success after skipping the due occurrence and keeping the next occurrence in the future" do
        occurrence

        expect(service.call).to eq(true)

        expect(occurrence.reload.status).to eq("skipped")
        expect(schedule.reload.status).to eq("paused")
        expect(schedule.next_occurrence_at > Time.current).to eq(true)
        expect(schedule.schedule_occurrences.count).to eq(2)
        expect(occurrence.publications.to_a).to eq([])
        expect(Publications::PublishJob).not_to have_been_enqueued
      end

      it "returns success after skipping an elapsed occurrence before its jitter time" do
        occurrence
        travel_to(scheduled_at + 1.minute)

        expect(service.call).to eq(true)

        expect(occurrence.reload.status).to eq("skipped")
        expect(schedule.reload.status).to eq("paused")
        expect(schedule.next_occurrence_at > Time.current).to eq(true)
        expect(occurrence.publications.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs.count).to eq(0)
      ensure
        travel_back
      end
    end

    context "when the due preflight cannot verify the connected destination" do
      it "returns failure after closing the occurrence without publishing" do
        preflight_errors = double("preflight errors", full_messages: [ "Instagram không phản hồi." ])
        preflight_service = double("preflight service", call: false, errors: preflight_errors)
        allow(PreflightReports::CreateService).to receive(:new).and_return(preflight_service)

        expect(service.call).to eq(false)

        expect(occurrence.reload.status).to eq("failed")
        expect(occurrence.safe_error_code).to eq("schedule_preflight_failed")
        expect(occurrence.publications.to_a).to eq([])
        expect(Publications::PublishJob).not_to have_been_enqueued
      end
    end

    context "when two workers process the same due occurrence" do
      let(:schedule) { create(:schedule, recurrence: "once") }
      let(:social_destination) { create(:social_destination, provider: "facebook") }
      let(:scheduled_at) { 10.minutes.ago }
      let(:occurrence) do
        create(
          :schedule_occurrence,
          schedule:,
          occurrence_key: scheduled_at.utc.iso8601(6),
          scheduled_at:,
          dispatch_at: scheduled_at + 5.minutes
        )
      end
      let(:preflight_report) do
        create(
          :preflight_report,
          render_version: schedule.render_version,
          checked_destination_ids: [ social_destination.id ],
          destination_results: { social_destination.id.to_s => { "status" => "ready" } }
        )
      end

      it "returns two successful outcomes with one Publication and one queued job", database_cleaner: :truncation do
        occurrence
        create(:schedule_destination, schedule:, social_destination:)
        preflight_service = double("preflight service", call: true, preflight_report:)
        allow(PreflightReports::CreateService).to receive(:new).and_return(preflight_service)
        ready = Queue.new
        start = Queue.new
        outcomes = Queue.new
        occurrence_id = occurrence.id
        worker_threads = 2.times.map do
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              ready << true
              start.pop
              service = described_class.new(schedule_occurrence_id: occurrence_id)
              service.call
              outcomes << service.success?
            end
          end
        end
        2.times { ready.pop }
        2.times { start << true }
        worker_threads.each(&:value)

        expect(2.times.map { outcomes.pop }).to eq([ true, true ])
        expect(occurrence.publications.count).to eq(1)
        expect(WorkflowRun.where(workflowable: occurrence.publications.sole).count).to eq(1)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs.length).to eq(1)
        expect(occurrence.reload.status).to eq("dispatched")
        expect(schedule.reload.status).to eq("completed")
      end
    end

    context "when one selected destination passes the current preflight report" do
      let(:schedule) { create(:schedule, recurrence: "once") }
      let(:facebook_destination) { create(:social_destination, provider: "facebook") }
      let(:instagram_destination) do
        connection = create(:social_connection, provider: "instagram")
        create(
          :social_destination,
          social_connection: connection,
          provider: "instagram",
          metadata: {
            "page_id" => "page-1",
            "instagram_business_account_id" => "ig-business-1",
            "instagram_account_type" => "BUSINESS"
          }
        )
      end
      let!(:facebook_schedule_destination) do
        create(:schedule_destination, schedule:, social_destination: facebook_destination, caption: "Facebook caption")
      end
      let!(:instagram_schedule_destination) do
        create(:schedule_destination, schedule:, social_destination: instagram_destination, caption: "Instagram caption")
      end
      let(:preflight_report) do
        create(
          :preflight_report,
          render_version: schedule.render_version,
          checked_destination_ids: [ facebook_destination.id, instagram_destination.id ],
          destination_results: {
            facebook_destination.id.to_s => { "status" => "ready" },
            instagram_destination.id.to_s => { "status" => "blocked" }
          }
        )
      end
      let(:preflight_service) { double("preflight service", call: true, preflight_report:) }

      before do
        allow(PreflightReports::CreateService).to receive(:new).and_return(preflight_service)
      end

      it "returns separate Publications and queues only the ready destination" do
        expect { service.call }.to change(Publication, :count).by(2)
          .and change(WorkflowRun, :count).by(1)
          .and have_enqueued_job(Publications::PublishJob).exactly(1).times

        facebook_publication = occurrence.publications.find_by!(social_destination: facebook_destination)
        instagram_publication = occurrence.publications.find_by!(social_destination: instagram_destination)

        expect(service.success?).to eq(true)
        expect(facebook_publication.status).to eq("approved")
        expect(facebook_publication.schedule_occurrence_key).to eq(
          "#{occurrence.occurrence_key}:#{facebook_destination.id}"
        )
        expect(instagram_publication.status).to eq("failed")
        expect(instagram_publication.schedule_occurrence_key).to eq(
          "#{occurrence.occurrence_key}:#{instagram_destination.id}"
        )
        expect(instagram_publication.safe_error_code).to eq("schedule_preflight_blocked")
        expect(occurrence.reload.status).to eq("dispatched")
        expect(occurrence.preflight_report).to eq(preflight_report)
        expect(WorkflowRun.find_by!(workflowable: facebook_publication).status).to eq("queued")
        expect(WorkflowRun.where(workflowable: instagram_publication).to_a).to eq([])
      end
    end

    context "when a TikTok Schedule destination has saved creator consent" do
      it "returns a Publication bound to the Schedule snapshot and current occurrence" do
        connection = create(:social_connection, provider: "tiktok", external_user_id: "creator-1")
        tiktok_destination = create(
          :social_destination,
          social_connection: connection,
          provider: "tiktok",
          external_id: "creator-1"
        )
        schedule.schedule_destinations.create!(
          social_destination: tiktok_destination,
          caption: "TikTok caption",
          consent_snapshot: {
            "tiktok_social_connection_id" => connection.id,
            "tiktok_creator_id" => "creator-1",
            "privacy_level" => "SELF_ONLY",
            "tiktok_confirmed_at" => Time.current.iso8601,
            "tiktok_schedule_id" => schedule.id
          }
        )
        report = create(
          :preflight_report,
          render_version: schedule.render_version,
          checked_destination_ids: [ tiktok_destination.id ],
          destination_results: { tiktok_destination.id.to_s => { "status" => "ready" } }
        )
        preflight_service = double("preflight service", call: true, preflight_report: report)
        allow(PreflightReports::CreateService).to receive(:new).and_return(preflight_service)

        service.call

        publication = occurrence.publications.sole
        consent_snapshot = publication.consent_snapshot

        expect(service.success?).to eq(true)
        expect(consent_snapshot.fetch("tiktok_schedule_id")).to eq(schedule.id)
        expect(consent_snapshot.fetch("tiktok_social_connection_id")).to eq(connection.id)
        expect(consent_snapshot.fetch("tiktok_creator_id")).to eq("creator-1")
        expect(consent_snapshot.fetch("tiktok_render_version_id")).to eq(schedule.render_version_id)
        expect(consent_snapshot.fetch("tiktok_publication_id")).to eq(publication.id)
      end
    end

    context "when a daily Schedule crosses a daylight-saving boundary" do
      it "returns the next occurrence at the same local clock time" do
        time_zone = ActiveSupport::TimeZone["America/New_York"]
        scheduled_at = time_zone.parse("2026-03-07 09:00:00")
        schedule = create(
          :schedule,
          recurrence: "daily",
          time_zone: "America/New_York",
          local_time: "09:00:00",
          next_occurrence_at: scheduled_at
        )
        social_destination = create(:social_destination, provider: "facebook")
        create(:schedule_destination, schedule:, social_destination:)
        occurrence = create(
          :schedule_occurrence,
          schedule:,
          occurrence_key: scheduled_at.utc.iso8601(6),
          scheduled_at:,
          dispatch_at: scheduled_at + 5.minutes
        )
        report = create(
          :preflight_report,
          render_version: schedule.render_version,
          checked_destination_ids: [ social_destination.id ],
          destination_results: { social_destination.id.to_s => { "status" => "ready" } }
        )
        preflight_service = double("preflight service", call: true, preflight_report: report)
        allow(PreflightReports::CreateService).to receive(:new).and_return(preflight_service)
        service = described_class.new(schedule_occurrence_id: occurrence.id)

        travel_to(time_zone.parse("2026-03-07 09:10:00")) { service.call }

        expect(schedule.reload.next_occurrence_at.in_time_zone(time_zone)).to eq(time_zone.parse("2026-03-08 09:00:00"))
        dispatch_window = schedule.next_occurrence_at + 5.minutes..schedule.next_occurrence_at + 30.minutes
        next_dispatch_at = schedule.schedule_occurrences.order(:scheduled_at).last.dispatch_at
        expect(dispatch_window.cover?(next_dispatch_at)).to eq(true)
      end
    end
  end
end
