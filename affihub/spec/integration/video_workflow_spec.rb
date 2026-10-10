require "rails_helper"
require "tempfile"

RSpec.describe "Video workflow integration", type: :service do
  describe "source, render, preflight, and publication" do
    let(:social_connection) do
      configuration = SocialConnections::ProviderConfiguration.for("facebook")
      create(:social_connection, provider: "facebook", scopes: configuration.fetch(:scopes))
    end
    let(:social_destination) do
      create(
        :social_destination,
        social_connection:,
        provider: "facebook",
        external_id: "facebook-page-1",
        name: "Page Bếp Nhà"
      )
    end
    let(:meta_client) { instance_double(Meta::Client) }

    before do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      allow(Meta::Client).to receive(:new).with(provider: :facebook).and_return(meta_client)
      allow(meta_client).to receive(:pages).and_return(
        [ { "id" => "facebook-page-1", "tasks" => [ "CREATE_CONTENT", "MODERATE" ] } ]
      )
    end

    it 'returns a reviewed manual Publication workflow with independent Drive and Sheets jobs' do
      video_project, source_asset, render_version = create_ready_render
      google_connections = create_google_connections
      preflight_report = create_ready_preflight(video_project:, render_version:, social_destination:)
      publication = create_manual_draft(video_project:, render_version:, preflight_report:, social_destination:)

      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      service = Publications::ConfirmService.new(
        video_project_id: video_project.id,
        publication_id: publication.id,
        preflight_report_id: preflight_report.id
      )

      expect(service.call).to eq(true)

      expect(source_asset.reload.status).to eq("ready")
      expect(render_version.reload.status).to eq("ready")
      expect(publication.reload.status).to eq("approved")
      expect(WorkflowRun.find_by!(workflowable: publication).status).to eq("queued")
      expect(DriveExport.where(render_version:, google_connection: google_connections.fetch(:drive)).count).to eq(1)
      expect(SheetSync.where(render_version:, google_connection: google_connections.fetch(:sheets)).count).to eq(1)
      expect(enqueued_job_classes).to eq(
        [ DriveExports::UploadJob, Publications::PublishJob, SheetSyncs::SyncJob ].sort_by(&:name)
      )
    end

    it 'returns a saved scheduled publication path with Drive and Sheets jobs before dispatch' do
      video_project, source_asset, render_version = create_ready_render
      google_connections = create_google_connections
      preflight_report = create_ready_preflight(video_project:, render_version:, social_destination:)
      service = Schedules::CreateService.new(
        video_project_id: video_project.id,
        render_version_id: render_version.id,
        preflight_report_id: preflight_report.id,
        scheduled_at: 1.hour.from_now,
        time_zone: "Asia/Ho_Chi_Minh",
        recurrence: "once",
        destination_settings: {
          social_destination.id.to_s => { "caption" => "Video mới từ AffiHub" }
        }
      )

      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      expect(service.call).to eq(true)

      expect(source_asset.reload.status).to eq("ready")
      expect(render_version.reload.status).to eq("ready")
      expect(service.schedule).to be_persisted
      expect(service.occurrence.reload.status).to eq("scheduled")
      expect(Publication.where(render_version:).count).to eq(0)
      expect(DriveExport.where(render_version:, google_connection: google_connections.fetch(:drive)).count).to eq(1)
      expect(SheetSync.where(render_version:, google_connection: google_connections.fetch(:sheets)).count).to eq(1)
      expect(enqueued_job_classes).to eq([ DriveExports::UploadJob, SheetSyncs::SyncJob ].sort_by(&:name))
    end

    def create_ready_render
      video_project = create(:video_project)
      tempfile = Tempfile.new([ "affihub-source", ".mp4" ])
      tempfile.binmode
      tempfile.write(File.binread(Rails.root.join("spec/fixtures/files/local_source.mp4")))
      tempfile.rewind
      upload = ActionDispatch::Http::UploadedFile.new(
        tempfile:,
        filename: "affihub-source.mp4",
        type: "video/mp4"
      )
      source_service = SourceAssets::CreateService.new(video_project:, file: upload)

      expect(source_service.call).to eq(true)

      source_asset = source_service.source_asset
      expect(SourceAssets::InspectJob.perform_now(source_asset.id)).to eq(true)
      source_asset.reload
      expect(source_asset.status).to eq("ready")

      duration = source_asset.media_metadata.fetch("duration_seconds")
      edit_config = {
        "schema_version" => 1,
        "segments" => [
          { "start_seconds" => 0.0, "end_seconds" => duration, "speed" => 1.0, "audio_mode" => "keep", "audio_volume" => 1.0 }
        ],
        "canvas" => { "mode" => "fit", "background" => { "type" => "blur" } },
        "filters" => { "brightness" => 0.0, "contrast" => 1.0 },
        "overlays" => [],
        "delogo_regions" => []
      }
      render_service = RenderVersions::CreateService.new(video_project:, source_asset:, edit_config:)

      expect(render_service.call).to eq(true)
      expect(RenderVersions::RenderJob.perform_now(render_service.render_version.id)).to eq(true)

      [ video_project, source_asset, render_service.render_version.reload ]
    ensure
      tempfile&.close!
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    def create_google_connections
      {
        drive: create(:google_connection, integration: "drive"),
        sheets: create(
          :google_connection,
          integration: "sheets",
          spreadsheet_id: "spreadsheet-integration-test",
          worksheet_title: "Video"
        )
      }
    end

    def create_ready_preflight(video_project:, render_version:, social_destination:)
      service = PreflightReports::CreateService.new(
        video_project_id: video_project.id,
        render_version_id: render_version.id,
        social_destination_ids: [ social_destination.id ]
      )
      allow(service).to receive(:step_live_worker_state).and_return(:running)

      expect(service.call).to eq(true)
      expect(service.preflight_report.ready_for?(render_version:, social_destination:)).to eq(true)

      service.preflight_report
    end

    def create_manual_draft(video_project:, render_version:, preflight_report:, social_destination:)
      service = Publications::CreateService.new(
        video_project_id: video_project.id,
        render_version_id: render_version.id,
        preflight_report_id: preflight_report.id,
        destination_captions: { social_destination.id.to_s => "Video mới từ AffiHub" }
      )

      expect(service.call).to eq(true)

      service.publications.sole
    end

    def enqueued_job_classes
      ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job.fetch(:job) }.sort_by(&:name)
    end
  end
end
