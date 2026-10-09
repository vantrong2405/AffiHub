require "rails_helper"

RSpec.describe "PreflightReports::CreateService", type: :service do
  let(:service_class) { PreflightReports::CreateService }
  describe "#call" do
    let(:video_project) { create(:video_project) }
    let(:youtube_publish_scopes) do
      Rails.application.config_for(:youtube).deep_symbolize_keys.dig(:oauth, :required_publish_scopes)
    end
    let(:source_metadata) do
      {
        "duration_seconds" => 2.0,
        "width" => 1080,
        "height" => 1920,
        "frame_rate" => 30,
        "video_codec" => "h264",
        "audio_codec" => "aac",
        "has_audio" => true
      }
    end
    let(:edit_config) do
      {
        "schema_version" => 1,
        "segments" => [ { "start_seconds" => 0.0, "end_seconds" => 2.0, "speed" => 1.0, "audio_mode" => "keep", "audio_volume" => 1.0 } ],
        "canvas" => { "mode" => "fit", "background" => { "type" => "blur" } },
        "filters" => { "brightness" => 0.0, "contrast" => 1.0 },
        "overlays" => [],
        "delogo_regions" => []
      }
    end
    let(:source_asset) do
      create(:source_asset, video_project:, status: "ready", media_metadata: source_metadata)
    end
    let(:render_version) do
      create(
        :render_version,
        video_project:,
        source_asset:,
        status: "ready",
        edit_config:,
        metadata: source_metadata
      )
    end
    let(:source_file) { File.open(Rails.root.join("spec/fixtures/files/edit_source.mp4")) }
    let(:render_file) { File.open(Rails.root.join("spec/fixtures/files/edit_source.mp4")) }
    let(:social_destinations) { [] }
    let(:service) do
      service_class.new(
        video_project_id: video_project.id,
        render_version_id: render_version.id,
        social_destination_ids: social_destinations.map(&:id)
      )
    end

    before do
      source_asset.file.attach(io: source_file, filename: "source.mp4", content_type: "video/mp4")
      render_version.file.attach(io: render_file, filename: "render.mp4", content_type: "video/mp4")
    end

    after do
      source_file.close
      render_file.close
    end

    it "returns a persisted report bound to the render and selected destinations at the check time" do
      social_destination = create(:social_destination)
      expected_time = Time.zone.local(2026, 10, 8, 12, 30, 0)
      scoped_service = service_class.new(
        video_project_id: video_project.id,
        render_version_id: render_version.id,
        social_destination_ids: [ social_destination.id ]
      )

      allow(Time).to receive(:current).and_return(expected_time)

      expect(scoped_service.call).to eq(true)

      preflight_report = PreflightReport.order(:id).last
      expect(preflight_report.render_version).to eq(render_version)
      expect(preflight_report.checked_destination_ids).to eq([ social_destination.id ])
      expect(preflight_report.checked_at).to eq(expected_time)
      transfer_check = preflight_report.destination_results
        .dig(social_destination.id.to_s, "checks", "media_transfer")
      expect(transfer_check.fetch("status")).to eq("passed")
      expect(transfer_check.fetch("protocol")).to eq("pages_reels_upload_session")
    end

    it "returns a warning that local processing is checked when no destination is selected" do
      expect(service.call).to eq(true)

      check = PreflightReport.order(:id).last.destination_results.dig("project", "checks", "publish_readiness")
      expect(check).to eq(
        "status" => "warning",
        "subject" => video_project.name,
        "reason" => "Chưa chọn Page, kênh hoặc tài khoản đích để kiểm tra khả năng đăng.",
        "action" => "Chọn destination rồi chạy preflight trước khi tạo Publication."
      )
    end

    it "returns the saved AI estimate without requesting a new quote" do
      estimated_at = "2026-10-08T12:00:00+07:00"
      create(
        :ai_generation,
        video_project:,
        status: "completed",
        estimate_snapshot: {
          "total_amount" => "0.50",
          "currency" => "USD",
          "required_costs_known" => false,
          "estimated_at" => estimated_at,
          "cost_breakdown" => {
            "muapi" => {
              "amount" => "0.50",
              "currency" => "USD",
              "provider" => "MuAPI",
              "source" => "MuAPI estimate-cost"
            }
          }
        }
      )
      estimate_request = stub_request(:post, /estimate-cost/)

      expect(service.call).to eq(true)

      check = PreflightReport.order(:id).last.destination_results.dig("project", "checks", "ai_estimate")
      expect(check.fetch("status")).to eq("warning")
      expect(check.fetch("total_amount")).to eq("0.50")
      expect(check.fetch("currency")).to eq("USD")
      expect(check.fetch("estimated_at")).to eq(estimated_at)
      expect(check.fetch("sources")).to eq([ "MuAPI estimate-cost" ])
      expect(estimate_request).not_to have_been_requested
    end

    it "returns a blocker when the attached source file is absent from storage" do
      source_blob = source_asset.file.blob
      allow(source_blob.service).to receive(:exist?).and_call_original
      allow(source_blob.service).to receive(:exist?).with(source_blob.key).and_return(false)

      expect(service.call).to eq(true)

      check = PreflightReport.order(:id).last.destination_results.dig("project", "checks", "source")
      expect(check.fetch("status")).to eq("blocked")
      expect(check.fetch("reason")).to eq("Source file không còn đọc được từ storage.")
    end

    it "returns a blocker when the attached render file is absent from storage" do
      render_blob = render_version.file.blob
      allow(render_blob.service).to receive(:exist?).and_call_original
      allow(render_blob.service).to receive(:exist?).with(render_blob.key).and_return(false)

      expect(service.call).to eq(true)

      check = PreflightReport.order(:id).last.destination_results.dig("project", "checks", "render")
      expect(check.fetch("status")).to eq("blocked")
      expect(check.fetch("reason")).to eq("Render file không còn đọc được từ storage.")
    end

    it "returns an actionable stale lease finding without changing its workflow" do
      lease_expires_at = 1.minute.ago.change(usec: 0)
      workflow_run = create(
        :workflow_run,
        workflowable: render_version,
        operation: "render_version_render",
        stage: "rendering",
        status: "running",
        worker_id: "render-worker-7",
        heartbeat_at: 2.minutes.ago,
        lease_expires_at:
      )

      expect(service.call).to eq(true)

      preflight_report = PreflightReport.order(:id).last
      worker_check = preflight_report.destination_results.dig("project", "checks", "worker")
      expect(worker_check.fetch("status")).to eq("blocked")
      expect(worker_check.fetch("stage")).to eq("rendering")
      expect(worker_check.fetch("worker_id")).to eq("render-worker-7")
      expect(worker_check.fetch("action")).to eq("Đối soát workflow trước khi nhận thêm side effect.")
      expect(workflow_run.reload.status).to eq("running")
      expect(workflow_run.reload.lease_expires_at).to eq(lease_expires_at)
    end

    it "returns a blocker when a workflow heartbeat is stale before its lease expires" do
      heartbeat_at = 6.minutes.ago.change(usec: 0)
      lease_expires_at = 5.minutes.from_now.change(usec: 0)
      workflow_run = create(
        :workflow_run,
        workflowable: render_version,
        operation: "render_version_render",
        stage: "rendering",
        status: "running",
        worker_id: "render-worker-8",
        heartbeat_at:,
        lease_expires_at:
      )

      expect(service.call).to eq(true)

      preflight_report = PreflightReport.order(:id).last
      worker_check = preflight_report.destination_results.dig("project", "checks", "worker")
      expect(worker_check.fetch("status")).to eq("blocked")
      expect(worker_check.fetch("worker_id")).to eq("render-worker-8")
      expect(workflow_run.reload.heartbeat_at).to eq(heartbeat_at)
      expect(workflow_run.reload.lease_expires_at).to eq(lease_expires_at)
    end

    context "when TikTok destinations are selected" do
      let(:social_connection) { create(:social_connection, provider: "tiktok", scopes: [ "video.publish" ]) }
      let(:tiktok_destination) do
        create(:social_destination, social_connection:, provider: "tiktok", external_id: "tiktok-creator-1")
      end
      let(:social_destinations) { [ tiktok_destination ] }
      let(:tiktok_client) { instance_double(TikTok::Client) }

      before do
        allow(TikTok::Client).to receive(:new).and_return(tiktok_client)
        allow(tiktok_client).to receive(:creator_info).and_return(
          "data" => {
            "privacy_level_options" => [ "SELF_ONLY" ],
            "comment_disabled" => false,
            "duet_disabled" => false,
            "stitch_disabled" => false
          },
          "error" => { "code" => "ok" }
        )
      end

      it "returns the local five-poster cap as a TikTok-only blocker" do
        create_tiktok_published_poster
        create_tiktok_published_poster
        create_tiktok_published_poster
        create_tiktok_published_poster
        create_tiktok_published_poster

        expect(service.call).to eq(true)

        check = PreflightReport.order(:id).last.destination_results
          .dig(tiktok_destination.id.to_s, "checks", "publishing_cap")
        expect(check.fetch("status")).to eq("blocked")
        expect(check.fetch("provider_error_code")).to eq("tiktok_app_creator_cap_reached")
        expect(tiktok_client).not_to have_received(:creator_info)
      end

      it "returns a blocked creator cap when TikTok reports spam_risk_too_many_posts" do
        allow(tiktok_client).to receive(:creator_info).and_return(
          "data" => {},
          "error" => { "code" => "spam_risk_too_many_posts" }
        )

        expect(service.call).to eq(true)

        check = PreflightReport.order(:id).last.destination_results
          .dig(tiktok_destination.id.to_s, "checks", "publishing_cap")
        expect(check.fetch("status")).to eq("blocked")
        expect(check.fetch("provider_error_code")).to eq("spam_risk_too_many_posts")
        expect(check.fetch("remaining_count")).to eq(nil)
        expect(check.fetch("reset_at")).to eq(nil)
      end

      it "returns a blocked app cap when TikTok reports reached_active_user_cap" do
        allow(tiktok_client).to receive(:creator_info).and_return(
          "data" => {},
          "error" => { "code" => "reached_active_user_cap" }
        )

        expect(service.call).to eq(true)

        check = PreflightReport.order(:id).last.destination_results
          .dig(tiktok_destination.id.to_s, "checks", "publishing_cap")
        expect(check.fetch("status")).to eq("blocked")
        expect(check.fetch("provider_error_code")).to eq("reached_active_user_cap")
        expect(check.fetch("remaining_count")).to eq(nil)
        expect(check.fetch("reset_at")).to eq(nil)
      end

      it "returns unavailable remaining-count data after a successful creator query" do
        expect(service.call).to eq(true)

        destination_checks = PreflightReport.order(:id).last.destination_results
          .fetch(tiktok_destination.id.to_s).fetch("checks")
        check = destination_checks.fetch("publishing_cap")
        expect(check.fetch("status")).to eq("unavailable")
        expect(check.fetch("remaining_count")).to eq(nil)
        expect(check.fetch("reset_at")).to eq(nil)
        expect(check.fetch("reason")).to eq("TikTok không cung cấp số bài đã dùng, số còn lại hoặc thời điểm đặt lại.")
        expect(destination_checks.fetch("content_policy").fetch("status")).to eq("passed")
        expect(destination_checks.fetch("media_transfer").fetch("status")).to eq("passed")
        expect(destination_checks.fetch("media_transfer").fetch("protocol")).to eq("tiktok_file_upload")
      end

      context "when the render contains a promotional text overlay" do
        let(:edit_config) do
          super().merge(
            "overlays" => [
              {
                "type" => "text",
                "text" => "Theo dõi AffiHub",
                "output_start_seconds" => 0.0,
                "output_end_seconds" => 2.0,
                "x" => 0.1,
                "y" => 0.8,
                "width" => 0.8,
                "height" => 0.1,
                "opacity" => 1.0
              }
            ]
          )
        end

        it "returns a TikTok blocker for the overlay added through the editor" do
          expect(service.call).to eq(true)

          check = PreflightReport.order(:id).last.destination_results
            .dig(tiktok_destination.id.to_s, "checks", "content_policy")
          expect(check.fetch("status")).to eq("blocked")
          expect(check.fetch("overlay_types")).to eq([ "text" ])
        end
      end
    end

    context "when Instagram destinations are selected" do
      let(:social_connection) do
        scopes = Rails.application.config_for(:meta).deep_symbolize_keys.dig(:providers, :instagram, :scopes)
        create(:social_connection, provider: "instagram", scopes:)
      end
      let(:instagram_destination) do
        create(:social_destination, social_connection:, provider: "instagram", external_id: "ig-business-1")
      end
      let(:social_destinations) { [ instagram_destination ] }
      let(:meta_client) { instance_double(Meta::Client) }
      let(:quota_response) do
        { "data" => [ { "quota_usage" => 12, "config" => { "quota_total" => 80, "quota_duration" => 86_400 } } ] }
      end

      before do
        allow(Meta::Client).to receive(:new).with(provider: :instagram).and_return(meta_client)
        allow(meta_client).to receive(:instagram_content_publishing_limit).and_return(quota_response)
      end

      it "returns the current Instagram publishing limit from the provider response" do
        expect(service.call).to eq(true)

        check = PreflightReport.order(:id).last.destination_results
          .dig(instagram_destination.id.to_s, "checks", "publishing_cap")
        expect(check.fetch("quota_usage")).to eq(12)
        expect(check.fetch("quota_total")).to eq(80)
        expect(check.fetch("quota_duration_seconds")).to eq(86_400)
        expect(check.fetch("status")).to eq("passed")
        transfer_check = PreflightReport.order(:id).last.destination_results
          .dig(instagram_destination.id.to_s, "checks", "media_transfer")
        expect(transfer_check.fetch("status")).to eq("passed")
        expect(transfer_check.fetch("protocol")).to eq("instagram_resumable_binary")
      end

      it "returns an unavailable Instagram cap without using a hardcoded quota" do
        allow(meta_client).to receive(:instagram_content_publishing_limit)
          .and_raise(Meta::Client::Error.new("network_request_failed"))

        expect(service.call).to eq(true)

        check = PreflightReport.order(:id).last.destination_results
          .dig(instagram_destination.id.to_s, "checks", "publishing_cap")
        expect(check.fetch("status")).to eq("unavailable")
        expect(check.fetch("quota_usage")).to eq(nil)
        expect(check.fetch("quota_total")).to eq(nil)
      end
    end

    it "returns YouTube counters per operation with the configured limit source and Console link" do
      social_connection = create(:social_connection, provider: "youtube", scopes: youtube_publish_scopes)
      youtube_destination = create(:social_destination, social_connection:, provider: "youtube")
      quota_configuration = Rails.application.config_for(:youtube).deep_symbolize_keys.fetch(:quota)
      usage_date = Time.current.in_time_zone(quota_configuration.fetch(:timezone)).to_date
      search_list_limit = quota_configuration.fetch(:buckets).fetch(:search_list).fetch(:daily_limit)
      videos_insert_limit = quota_configuration.fetch(:buckets).fetch(:videos_insert).fetch(:daily_limit)
      create(:youtube_quota_counter, bucket: "search.list", usage_date:, requests_count: 3)
      create(:youtube_quota_counter, bucket: "videos.insert", usage_date:, requests_count: 7)
      youtube_service = service_class.new(
        video_project_id: video_project.id,
        render_version_id: render_version.id,
        social_destination_ids: [ youtube_destination.id ]
      )

      expect(youtube_service.call).to eq(true)

      check = PreflightReport.order(:id).last.destination_results
        .dig(youtube_destination.id.to_s, "checks", "quota")
      expect(check.fetch("operations")).to eq(
        "search.list" => {
          "status" => "passed",
          "subject" => "YouTube search.list",
          "reason" => "Quota local của search.list chưa đạt giới hạn đang cấu hình.",
          "action" => "Không cần khắc phục.",
          "observed_count" => 3,
          "daily_limit" => search_list_limit
        },
        "videos.insert" => {
          "status" => "passed",
          "subject" => "YouTube videos.insert",
          "reason" => "Quota local của videos.insert chưa đạt giới hạn đang cấu hình.",
          "action" => "Không cần khắc phục.",
          "observed_count" => 7,
          "daily_limit" => videos_insert_limit
        }
      )
      expect(check.fetch("limit_source_url")).to eq("https://developers.google.com/youtube/v3/determine_quota_cost")
      expect(check.fetch("console_url")).to eq("https://console.cloud.google.com/apis/api/youtube.googleapis.com/quotas")
      expect(check.fetch("scope_notice")).to eq("Bộ đếm chỉ gồm request do AffiHub tạo; Google Cloud Console là nguồn tổng usage authoritative.")
      transfer_check = PreflightReport.order(:id).last.destination_results
        .dig(youtube_destination.id.to_s, "checks", "media_transfer")
      expect(transfer_check.fetch("status")).to eq("passed")
      expect(transfer_check.fetch("protocol")).to eq("youtube_resumable_videos_insert")
    end

    it "returns an unavailable transfer check when YouTube upload configuration is incomplete" do
      youtube_configuration = Rails.application.config_for(:youtube).deep_symbolize_keys.except(:upload_base_url)
      allow(Rails.application).to receive(:config_for).and_call_original
      allow(Rails.application).to receive(:config_for).with(:youtube).and_return(youtube_configuration)
      social_connection = create(:social_connection, provider: "youtube", scopes: youtube_publish_scopes)
      youtube_destination = create(:social_destination, social_connection:, provider: "youtube")
      youtube_service = service_class.new(
        video_project_id: video_project.id,
        render_version_id: render_version.id,
        social_destination_ids: [ youtube_destination.id ]
      )

      expect(youtube_service.call).to eq(true)

      check = PreflightReport.order(:id).last.destination_results
        .dig(youtube_destination.id.to_s, "checks", "media_transfer")
      expect(check.fetch("status")).to eq("unavailable")
      expect(check.fetch("missing_configuration")).to eq("upload_base_url")
    end

    it "returns a YouTube search-list quota blocker without changing the Instagram cap check" do
      instagram_scopes = Rails.application.config_for(:meta).deep_symbolize_keys.dig(:providers, :instagram, :scopes)
      instagram_connection = create(:social_connection, provider: "instagram", scopes: instagram_scopes)
      instagram_destination = create(:social_destination, social_connection: instagram_connection, provider: "instagram")
      youtube_connection = create(:social_connection, provider: "youtube", scopes: youtube_publish_scopes)
      youtube_destination = create(:social_destination, social_connection: youtube_connection, provider: "youtube")
      quota_configuration = Rails.application.config_for(:youtube).deep_symbolize_keys.fetch(:quota)
      usage_date = Time.current.in_time_zone(quota_configuration.fetch(:timezone)).to_date
      search_list_limit = quota_configuration.fetch(:buckets).fetch(:search_list).fetch(:daily_limit)
      create(:youtube_quota_counter, bucket: "search.list", usage_date:, requests_count: search_list_limit)
      service_with_two_destinations = service_class.new(
        video_project_id: video_project.id,
        render_version_id: render_version.id,
        social_destination_ids: [ instagram_destination.id, youtube_destination.id ]
      )
      meta_client = instance_double(Meta::Client)
      allow(Meta::Client).to receive(:new).with(provider: :instagram).and_return(meta_client)
      allow(meta_client).to receive(:instagram_content_publishing_limit).and_return(
        "data" => [ { "quota_usage" => 12, "config" => { "quota_total" => 80, "quota_duration" => 86_400 } } ]
      )

      expect(service_with_two_destinations.call).to eq(true)

      results = PreflightReport.order(:id).last.destination_results
      expect(results.dig(youtube_destination.id.to_s, "checks", "quota", "operations", "search.list", "status")).to eq("blocked")
      expect(results.dig(instagram_destination.id.to_s, "checks", "publishing_cap", "status")).to eq("passed")
    end

    it "returns persisted MPT task state after reloading the generation and keeps paid submission read-only" do
      ai_generation = create(
        :ai_generation,
        video_project:,
        status: "processing",
        correlation_id: "mpt-correlation-123",
        task_id: "mpt-task-123"
      )
      reloaded_task_id = AiGeneration.find(ai_generation.id).task_id
      task_request = stub_request(:get, "http://mpt.test/api/v1/tasks/#{reloaded_task_id}")
        .to_return(status: 200, body: { status: 200, data: { task_id: reloaded_task_id, state: 4 } }.to_json)
      paid_submission = stub_request(:post, "http://mpt.test/api/v1/videos")
      recovery_verified_at = "2026-10-08T11:45:00+07:00"
      mpt_configuration = Rails.application.config_for(:money_printer_turbo).deep_symbolize_keys
      verified_configuration = mpt_configuration.slice(:base_url, :version, :commit)
      mpt_configuration = mpt_configuration.deep_merge(
        preflight: {
          restart_recovery_verified: true,
          restart_recovery_verified_at: recovery_verified_at,
          restart_recovery_verified_for: verified_configuration
        }
      )
      allow(Rails.application).to receive(:config_for).and_call_original
      allow(Rails.application).to receive(:config_for).with(:money_printer_turbo).and_return(mpt_configuration)
      social_connection = create(:social_connection, provider: "youtube", scopes: youtube_publish_scopes)
      social_destination = create(:social_destination, social_connection:, provider: "youtube")
      service_with_destination = service_class.new(
        video_project_id: video_project.id,
        render_version_id: render_version.id,
        social_destination_ids: [ social_destination.id ]
      )

      expect(service_with_destination.call).to eq(true)

      ai_check = PreflightReport.order(:id).last.destination_results.dig("project", "checks", "paid_ai")
      expect(ai_check.fetch("status")).to eq("passed")
      expect(ai_check.fetch("task_id")).to eq("mpt-task-123")
      expect(ai_check.fetch("restart_recovery_verified_at")).to eq(recovery_verified_at)
      expect(task_request).to have_been_requested.once
      expect(WebMock).not_to have_requested(:post, "http://mpt.test/api/v1/videos")
      expect(ai_generation.reload.task_id).to eq("mpt-task-123")
    end

    it "returns a blocker when MPT recovery is marked verified without a verification time" do
      ai_generation = create(
        :ai_generation,
        video_project:,
        status: "processing",
        correlation_id: "mpt-correlation-no-time",
        task_id: "mpt-task-no-time"
      )
      task_request = stub_request(:get, "http://mpt.test/api/v1/tasks/#{ai_generation.task_id}")
      mpt_configuration = Rails.application.config_for(:money_printer_turbo).deep_symbolize_keys
      verified_configuration = mpt_configuration.slice(:base_url, :version, :commit)
      mpt_configuration = mpt_configuration.deep_merge(
        preflight: {
          restart_recovery_verified: true,
          restart_recovery_verified_at: nil,
          restart_recovery_verified_for: verified_configuration
        }
      )
      allow(Rails.application).to receive(:config_for).and_call_original
      allow(Rails.application).to receive(:config_for).with(:money_printer_turbo).and_return(mpt_configuration)

      expect(service.call).to eq(true)

      check = PreflightReport.order(:id).last.destination_results.dig("project", "checks", "paid_ai")
      expect(check.fetch("status")).to eq("blocked")
      expect(check.fetch("restart_recovery_verified_at")).to eq(nil)
      expect(task_request).not_to have_been_requested
    end

    it "returns a blocker when the MPT recovery evidence belongs to another configuration" do
      ai_generation = create(
        :ai_generation,
        video_project:,
        status: "processing",
        correlation_id: "mpt-correlation-old-config",
        task_id: "mpt-task-old-config"
      )
      task_request = stub_request(:get, "http://mpt.test/api/v1/tasks/#{ai_generation.task_id}")
      mpt_configuration = Rails.application.config_for(:money_printer_turbo).deep_symbolize_keys
      verified_configuration = mpt_configuration.slice(:base_url, :version, :commit)
        .merge(base_url: "http://previous-money-printer-turbo:8080")
      mpt_configuration = mpt_configuration.deep_merge(
        preflight: {
          restart_recovery_verified: true,
          restart_recovery_verified_at: "2026-10-08T11:45:00+07:00",
          restart_recovery_verified_for: verified_configuration
        }
      )
      allow(Rails.application).to receive(:config_for).and_call_original
      allow(Rails.application).to receive(:config_for).with(:money_printer_turbo).and_return(mpt_configuration)

      expect(service.call).to eq(true)

      check = PreflightReport.order(:id).last.destination_results.dig("project", "checks", "paid_ai")
      expect(check.fetch("status")).to eq("blocked")
      expect(check.fetch("recovery_configuration_matches")).to eq(false)
      expect(task_request).not_to have_been_requested
    end

    it "returns paid AI readiness independently from social destination checks when MPT recovery is unavailable" do
      social_connection = create(:social_connection, provider: "youtube", scopes: youtube_publish_scopes)
      youtube_destination = create(:social_destination, social_connection:, provider: "youtube")
      service_with_destination = service_class.new(
        video_project_id: video_project.id,
        render_version_id: render_version.id,
        social_destination_ids: [ youtube_destination.id ]
      )

      expect(service_with_destination.call).to eq(true)

      results = PreflightReport.order(:id).last.destination_results
      expect(results.dig("project", "checks", "paid_ai", "status")).to eq("blocked")
      expect(results.dig(youtube_destination.id.to_s, "checks", "quota", "status")).to eq("passed")
    end

    it "returns independent destination results when one provider read fails" do
      instagram_scopes = Rails.application.config_for(:meta).deep_symbolize_keys.dig(:providers, :instagram, :scopes)
      instagram_connection = create(:social_connection, provider: "instagram", scopes: instagram_scopes)
      instagram_destination = create(:social_destination, social_connection: instagram_connection, provider: "instagram")
      youtube_connection = create(:social_connection, provider: "youtube", scopes: youtube_publish_scopes)
      youtube_destination = create(:social_destination, social_connection: youtube_connection, provider: "youtube")
      service_with_two_destinations = service_class.new(
        video_project_id: video_project.id,
        render_version_id: render_version.id,
        social_destination_ids: [ instagram_destination.id, youtube_destination.id ]
      )
      meta_client = instance_double(Meta::Client)
      allow(Meta::Client).to receive(:new).with(provider: :instagram).and_return(meta_client)
      allow(meta_client).to receive(:instagram_content_publishing_limit)
        .and_raise(Meta::Client::Error.new("network_request_failed"))

      expect(service_with_two_destinations.call).to eq(true)

      results = PreflightReport.order(:id).last.destination_results
      expect(results.dig(instagram_destination.id.to_s, "checks", "publishing_cap", "status")).to eq("unavailable")
      expect(results.dig(youtube_destination.id.to_s, "checks", "quota", "status")).to eq("passed")
    end

    it "returns an audit report without publishing, rendering, changing source state, or submitting paid AI" do
      social_connection = create(:social_connection, provider: "youtube", scopes: youtube_publish_scopes)
      social_destination = create(:social_destination, social_connection:, provider: "youtube")
      create(:publication, render_version:, social_destination:, status: "draft")
      source_updated_at = source_asset.reload.updated_at
      render_updated_at = render_version.reload.updated_at
      render_edit_config = render_version.edit_config
      publication_count = Publication.count
      render_count = RenderVersion.count
      generation_count = AiGeneration.count
      attempt_count = OutboundAttempt.count
      paid_submission = stub_request(:post, "http://mpt.test/api/v1/videos")

      expect(service.call).to eq(true)

      expect(Publication.count).to eq(publication_count)
      expect(RenderVersion.count).to eq(render_count)
      expect(AiGeneration.count).to eq(generation_count)
      expect(OutboundAttempt.count).to eq(attempt_count)
      expect(source_asset.reload.updated_at).to eq(source_updated_at)
      expect(render_version.reload.updated_at).to eq(render_updated_at)
      expect(render_version.reload.edit_config).to eq(render_edit_config)
      expect(WebMock).not_to have_requested(:post, "http://mpt.test/api/v1/videos")
      expect(WebMock).not_to have_requested(:post, /(?:tiktokapis\.com|facebook\.com|googleapis\.com)/)
      expect(paid_submission).not_to have_been_requested
    end
  end

  def create_tiktok_published_poster
    social_connection = create(:social_connection, provider: "tiktok")
    social_destination = create(:social_destination, social_connection:, provider: "tiktok")
    publication = create(:publication, social_destination:, status: "published")
    workflow_run = create(
      :workflow_run,
      workflowable: publication,
      operation: "publication_publish",
      stage: "publish",
      status: "completed"
    )
    create(
      :outbound_attempt,
      workflow_run:,
      stage: "publish",
      status: "confirmed",
      request_started_at: 1.hour.ago,
      sender_stopped_at: 1.hour.ago
    )
  end
end
