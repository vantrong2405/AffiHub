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

    it "returns all generated media references after MPT completes" do
      call_result

      expect(service.output.fetch(:clips)).to eq([ "scene-1.mp4" ])
      expect(service.output.fetch(:voiceover)).to eq("voiceover.wav")
      expect(service.output.fetch(:subtitle)).to eq("subtitles.srt")
      expect(service.output.fetch(:preview_mp4)).to eq("combined.mp4")
    end

    context "when MPT is still processing the task" do
      let(:task_result) { super().merge(state: 4) }

      it "returns false and reports that the MPT task is still incomplete" do
        expect(call_result).to be(false)
        expect(service.errors.full_messages).to eq([ "MPT task chưa hoàn tất." ])
      end
    end

    context "when the completed task has no combined MP4" do
      let(:task_result) { super().except(:combined_videos) }

      it "returns false and reports the missing required output" do
        expect(call_result).to be(false)
        expect(service.errors.full_messages).to eq([ "MPT task thiếu file video, voiceover hoặc subtitle." ])
      end
    end
  end
end
