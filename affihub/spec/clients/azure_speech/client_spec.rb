# frozen_string_literal: true

require "rails_helper"

RSpec.describe AzureSpeech::Client, type: :service do
  let(:client) { described_class.new }
  let(:speech_text) { "Xin chào & <video>" }
  let(:response_audio) { "RIFF0000WAVEaudio-data" }

  describe "#synthesize" do
    let(:speech_request) do
      stub_request(:post, "https://azure-speech.test/cognitiveservices/v1")
        .with(
          headers: {
            "Ocp-Apim-Subscription-Key" => "affihub-test-key",
            "Ocp-Apim-Subscription-Region" => "test-region",
            "X-Microsoft-OutputFormat" => "riff-24khz-16bit-mono-pcm"
          },
          body: '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="vi-VN"><voice name="vi-VN-HoaiMyNeural">Xin chào &amp; &lt;video&gt;</voice></speak>'
        )
        .to_return(status: 200, body: response_audio)
    end
    subject(:audio_data) { client.synthesize(text: speech_text, voice: "vi-VN-HoaiMyNeural") }

    before { speech_request }

    it "returns escaped SSML audio from Azure Speech" do
      expect(audio_data).to eq(response_audio)
    end

    it "sends one request to Azure Speech" do
      audio_data

      expect(speech_request).to have_been_requested.once
    end

    context "when Azure rejects the request" do
      let(:speech_request) do
        stub_request(:post, "https://azure-speech.test/cognitiveservices/v1")
          .to_return(status: 401, body: "affihub-test-key provider-secret")
      end

      it "returns a sanitized provider error" do
        expect { audio_data }.to raise_error(described_class::Error, "http_401")
      end
    end
  end
end
