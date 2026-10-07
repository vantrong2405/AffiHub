# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::TtsFallbackService, type: :service do
  let(:speech_text) { "Xin chào, đây là video tiếng Việt." }
  let(:azure_voice) { "vi-VN-HoaiMyNeural" }
  let(:vieneu_audio) { "RIFF0000WAVEaudio-data" }
  let(:azure_audio) { "RIFF0000WAVEazure-audio" }
  let(:azure_estimate) do
    {
      amount: "0.01",
      currency: "USD",
      source: "Azure Speech pricing estimate",
      estimated_at: Time.current,
      input_snapshot: { text: speech_text, voice: azure_voice }
    }
  end
  let(:azure_consented) { false }
  let(:service) do
    described_class.new(
      text: speech_text,
      azure_estimate: azure_estimate,
      azure_consented: azure_consented
    )
  end
  let(:vieneu_request) do
    stub_request(:post, "http://vieneu.test/v1/audio/speech")
      .with(body: {
        "model" => "vieneu-v3-turbo",
        "input" => speech_text,
        "voice" => "Mai Anh",
        "response_format" => "wav",
        "speed" => 1.0
      })
      .to_return(status: 200, body: vieneu_audio)
  end
  let(:azure_request) do
    stub_request(:post, %r{cognitiveservices/v1\z})
      .to_return(status: 200, body: azure_audio)
  end

  describe "#call" do
    subject(:call_result) { service.call }

    before do
      vieneu_request
      azure_request
    end

    it "returns VieNeu WAV audio from one provider request" do
      expect(call_result).to be(true)

      expect(service.provider).to eq("vieneu")
      expect(service.audio_data).to eq(vieneu_audio)
      expect(vieneu_request).to have_been_requested.once
    end

    context "when VieNeu fails and the Azure quote is missing" do
      let(:vieneu_audio) { "provider-error" }
      let(:azure_estimate) { {} }
      let(:azure_consented) { true }

      it "returns an unavailable result without automatic provider fallback" do
        call_result

        expect(service.success?).to be(false)
        expect(azure_request).not_to have_been_requested
        expect(WebMock).not_to have_requested(:any, %r{edge-tts})
      end
    end

    context "when VieNeu fails and Azure consent is missing" do
      let(:vieneu_audio) { "provider-error" }
      let(:azure_consented) { false }

      it "returns an unavailable result without calling Azure" do
        call_result

        expect(service.success?).to be(false)
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when VieNeu fails and Azure has a current confirmed quote" do
      let(:vieneu_audio) { "provider-error" }
      let(:azure_consented) { true }

      it "returns Azure WAV audio after one fallback request" do
        call_result

        expect(service.success?).to be(true)
        expect(service.provider).to eq("azure_speech")
        expect(service.audio_data).to eq(azure_audio)
        expect(azure_request).to have_been_requested.once
      end
    end

    context "when the Azure quote is stale" do
      let(:vieneu_audio) { "provider-error" }
      let(:azure_consented) { true }
      let(:azure_estimate) { super().merge(estimated_at: 2.hours.ago) }

      it "returns an unavailable result without calling Azure" do
        call_result

        expect(service.success?).to be(false)
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when the Azure quote belongs to different narration text" do
      let(:vieneu_audio) { "provider-error" }
      let(:azure_consented) { true }
      let(:azure_estimate) do
        super().merge(input_snapshot: { text: "Different narration", voice: azure_voice })
      end

      it "returns an unavailable result without calling Azure" do
        call_result

        expect(service.success?).to be(false)
        expect(azure_request).not_to have_been_requested
      end
    end
  end
end
