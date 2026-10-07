# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::CompleteService, type: :service do
  let(:task_result) do
    {
      state: 1,
      videos: [ "scene-1.mp4" ],
      combined_videos: [ "combined.mp4" ],
      audio_file: "voiceover.wav",
      subtitle_path: "subtitles.srt"
    }
  end
  let(:service) { described_class.new(task_result: task_result) }

  describe "#call" do
    subject(:call_result) { service.call }

    it "returns the generated clip references" do
      call_result

      expect(service.output.fetch(:clips)).to eq([ "scene-1.mp4" ])
    end

    it "returns the generated voiceover reference" do
      call_result

      expect(service.output.fetch(:voiceover)).to eq("voiceover.wav")
    end

    it "returns the generated subtitle reference" do
      call_result

      expect(service.output.fetch(:subtitle)).to eq("subtitles.srt")
    end

    it "returns the generated preview reference" do
      call_result

      expect(service.output.fetch(:preview_mp4)).to eq("combined.mp4")
    end

    context "when MPT is still processing the task" do
      let(:task_result) { super().merge(state: 4) }

      it "returns false while MPT is still processing the task" do
        expect(call_result).to be(false)
      end

      it "records an incomplete-task error" do
        call_result

        expect(service.errors.full_messages).to eq([ "MPT task chưa hoàn tất." ])
      end
    end

    context "when the completed task has no combined MP4" do
      let(:task_result) { super().except(:combined_videos) }

      it "returns false when the preview is missing" do
        expect(call_result).to be(false)
      end

      it "records an output error when the preview is missing" do
        call_result

        expect(service.errors.full_messages).to eq([ "MPT task thiếu file video, voiceover hoặc subtitle." ])
      end
    end
  end
end
