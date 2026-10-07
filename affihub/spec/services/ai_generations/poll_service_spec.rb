# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::PollService, type: :service do
  let(:video_project) { create(:video_project) }
  let(:ai_generation) do
    create(
      :ai_generation,
      video_project:,
      status: "processing",
      task_id: "mpt-task-123"
    )
  end
  let(:task_result) do
    {
      task_id: "mpt-task-123",
      state: 1,
      videos: [ "/tasks/mpt-task-123/scene-1.mp4" ],
      combined_videos: [ "/tasks/mpt-task-123/preview.mp4" ],
      audio_file: "/tasks/mpt-task-123/voiceover.wav",
      subtitle_path: "/tasks/mpt-task-123/subtitles.srt"
    }
  end
  let(:task_request) do
    stub_request(:get, "http://mpt.test/api/v1/tasks/mpt-task-123")
      .to_return(status: 200, body: { status: 200, data: task_result }.to_json)
  end
  let(:clip_download) do
    stub_request(:get, "http://mpt.test/api/v1/download/mpt-task-123/scene-1.mp4")
      .to_return(status: 200, body: "scene-video-bytes")
  end
  let(:preview_download) do
    stub_request(:get, "http://mpt.test/api/v1/download/mpt-task-123/preview.mp4")
      .to_return(status: 200, body: "preview-video-bytes")
  end
  let(:voiceover_download) do
    stub_request(:get, "http://mpt.test/api/v1/download/mpt-task-123/voiceover.wav")
      .to_return(status: 200, body: "voiceover-audio-bytes")
  end
  let(:subtitle_download) do
    stub_request(:get, "http://mpt.test/api/v1/download/mpt-task-123/subtitles.srt")
      .to_return(status: 200, body: "subtitle-text")
  end
  let(:service) { described_class.new(ai_generation_id: ai_generation.id) }

  describe "#call" do
    subject(:call_result) { service.call }

    before do
      ai_generation
      task_request
      clip_download
      preview_download
      voiceover_download
      subtitle_download
    end

    it "stores completed MPT outputs as generation attachments and a source asset" do
      expect(call_result).to be(true)

      expect(ai_generation.reload.status).to eq("completed")
      expect(ai_generation.provider_state).to eq(1)
      expect(ai_generation.clips.map { |clip| clip.filename.to_s }).to eq([ "scene-1.mp4" ])
      expect(ai_generation.clips.first.download).to eq("scene-video-bytes")
      expect(ai_generation.voiceover.download).to eq("voiceover-audio-bytes")
      expect(ai_generation.subtitle.download).to eq("subtitle-text")
      expect(ai_generation.preview_video.download).to eq("preview-video-bytes")
      expect(ai_generation.source_asset.source_type).to eq("ai_generated")
      expect(ai_generation.source_asset.status).to eq("pending")
      expect(ai_generation.source_asset.file.download).to eq("preview-video-bytes")
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:job] })
        .to include(SourceAssets::InspectJob)
    end

    context "when MPT is still processing the task" do
      let(:task_result) { super().merge(state: 4) }

      it "keeps the generation processing and requests another poll" do
        expect(call_result).to be(true)

        expect(ai_generation.reload.status).to eq("processing")
        expect(ai_generation.provider_state).to eq(4)
        expect(service.retry_poll?).to be(true)
        expect(WebMock).not_to have_requested(:get, %r{/api/v1/download/})
      end
    end

    context "when MPT reports a failed task" do
      let(:task_result) { super().slice(:task_id).merge(state: -1) }
      let(:ai_generation_scene) do
        create(:ai_generation_scene, ai_generation:, status: "processing")
      end

      it "marks the generation failed without downloading outputs" do
        ai_generation_scene

        expect(call_result).to be(true)

        expect(ai_generation.reload.status).to eq("failed")
        expect(ai_generation.provider_state).to eq(-1)
        expect(ai_generation_scene.reload.status).to eq("failed")
        expect(ai_generation.source_asset).to be_nil
        expect(WebMock).not_to have_requested(:get, %r{/api/v1/download/})
      end
    end

    context "when the task ID does not match the saved generation" do
      let(:task_result) { super().merge(task_id: "different-task") }

      it "marks the generation failed without downloading another task's files" do
        expect(call_result).to be(true)

        expect(ai_generation.reload.status).to eq("failed")
        expect(ai_generation.safe_error_code).to eq("task_identity_mismatch")
        expect(ai_generation.source_asset).to be_nil
        expect(WebMock).not_to have_requested(:get, %r{/api/v1/download/})
      end
    end

    context "when MPT does not return a valid output set" do
      let(:task_result) { super().merge(subtitle_path: nil) }

      it "marks the generation failed without downloading partial outputs" do
        expect(call_result).to be(true)

        expect(ai_generation.reload.status).to eq("failed")
        expect(ai_generation.safe_error_code).to eq("invalid_provider_output")
        expect(ai_generation.source_asset).to be_nil
        expect(WebMock).not_to have_requested(:get, %r{/api/v1/download/})
      end
    end

    context "when MPT cannot be reached while reading task state" do
      let(:task_request) do
        stub_request(:get, "http://mpt.test/api/v1/tasks/mpt-task-123").to_timeout
      end

      it "keeps the generation processing and requests another poll" do
        expect(call_result).to be(false)

        expect(ai_generation.reload.status).to eq("processing")
        expect(ai_generation.safe_error_code).to eq("network_request_failed")
        expect(service.retry_poll?).to be(true)
        expect(WebMock).not_to have_requested(:get, %r{/api/v1/download/})
      end
    end

    context "when the generation is already completed" do
      let(:ai_generation) do
        create(:ai_generation, video_project:, status: "completed", task_id: "mpt-task-123")
      end

      it "does not read MPT state or schedule another poll" do
        expect(call_result).to be(true)

        expect(service.retry_poll?).to be(false)
        expect(task_request).not_to have_been_requested
      end
    end

    context "when an MPT completion poll is repeated" do
      before do
        ActiveJob::Base.queue_adapter.enqueued_jobs.clear
        service.call
      end

      it "does not duplicate persisted output or inspection work" do
        repeated_service = described_class.new(ai_generation_id: ai_generation.id)

        expect(repeated_service.call).to be(true)
        expect(video_project.source_assets.count).to eq(1)
        expect(ai_generation.reload.clips_attachments.count).to eq(1)
        expect(ai_generation.voiceover.attached?).to be(true)
        expect(ai_generation.subtitle.attached?).to be(true)
        expect(ai_generation.preview_video.attached?).to be(true)
        expect(task_request).to have_been_requested.once
        inspect_job_count = ActiveJob::Base.queue_adapter.enqueued_jobs.count do |job|
          job[:job] == SourceAssets::InspectJob
        end
        expect(inspect_job_count).to eq(1)
      end
    end

    context "when an output download fails" do
      let(:preview_download) do
        stub_request(:get, "http://mpt.test/api/v1/download/mpt-task-123/preview.mp4")
          .to_timeout
      end

      it "keeps the generation incomplete and retries output persistence" do
        expect(call_result).to be(false)

        expect(ai_generation.reload.status).to eq("processing")
        expect(ai_generation.source_asset).to be_nil
        expect(ai_generation.clips_attachments).to be_empty
        expect(ai_generation.voiceover.attached?).to be(false)
        expect(ai_generation.subtitle.attached?).to be(false)
        expect(ai_generation.preview_video.attached?).to be(false)
        expect(service.retry_poll?).to be(true)
      end
    end
  end
end
