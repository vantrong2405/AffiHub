# frozen_string_literal: true

require "rails_helper"

RSpec.describe Vieneu::Client, type: :service do
  let(:client) { described_class.new }
  let(:speech_inputs) { { text: "Xin chào.", voice: "Mai Anh" } }
  let(:response_audio) { "RIFF0000WAVEaudio-data" }

  describe "#synthesize" do
    let(:speech_request) do
      stub_request(:post, "http://vieneu.test/v1/audio/speech")
        .with(
          headers: { "Authorization" => "Bearer affihub-test-key" },
          body: {
            "model" => "vieneu-v3-turbo",
            "input" => "Xin chào.",
            "voice" => "Mai Anh",
            "response_format" => "wav",
            "speed" => 1.0
          }
        )
        .to_return(status: 200, body: response_audio)
    end
    subject(:audio_data) { client.synthesize(**speech_inputs) }

    before { speech_request }

    it "returns WAV audio from the configured VieNeu endpoint" do
      expect(audio_data).to eq(response_audio)
    end

    it "sends one request to the configured VieNeu endpoint" do
      audio_data

      expect(speech_request).to have_been_requested.once
    end

    context "when VieNeu responds with non-WAV audio" do
      let(:response_audio) { "mp3-audio" }

      it "returns a sanitized format error" do
        expect { audio_data }.to raise_error(described_class::Error, "invalid_wav_response")
      end
    end
  end
end
