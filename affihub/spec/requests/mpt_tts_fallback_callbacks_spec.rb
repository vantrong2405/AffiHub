# frozen_string_literal: true

require "rails_helper"
require "openssl"

RSpec.describe "MPT TTS fallback callbacks", type: :request do
  let(:callback_secret) { "affihub-test-callback-secret" }
  let(:narration) { "A short summer skincare story." }
  let(:voice) { "vi-VN-HoaiMyNeural" }
  let(:azure_audio) { "RIFF0000WAVEazure-audio" }
  let(:estimate_snapshot) do
    {
      provider: "azure_speech",
      amount: "0.01",
      currency: "USD",
      source: "Azure Speech pricing estimate",
      estimated_at: 1.minute.ago.iso8601,
      input_snapshot: { narration:, voice: }
    }
  end
  let(:consent_snapshot) do
    { confirmed: true, confirmed_at: 1.minute.ago.iso8601, estimate: estimate_snapshot }
  end
  let(:ai_generation) do
    create(:ai_generation, status: "processing", estimate_snapshot: { currency: "USD" })
  end
  let(:ai_generation_scene) do
    create(
      :ai_generation_scene,
      ai_generation:,
      scene_index: 0,
      status: "processing",
      narration_snapshot: narration,
      voice_name: voice,
      estimate_snapshot:,
      consent_snapshot:
    )
  end
  let(:workflow_run) { create(:workflow_run, workflowable: ai_generation_scene, operation: "tts_fallback") }
  let(:timestamp) { Time.current.to_i.to_s }
  let(:raw_body) do
    {
      correlation_id: ai_generation.correlation_id,
      scene_index: ai_generation_scene.scene_index,
      narration:,
      voice:
    }.to_json
  end
  let(:signature) do
    OpenSSL::HMAC.hexdigest("SHA256", callback_secret, "#{timestamp}.#{raw_body}")
  end
  let(:azure_request) do
    stub_request(:post, "https://azure-speech.test/cognitiveservices/v1")
      .to_return(status: 200, body: azure_audio)
  end

  before do
    workflow_run
    ai_generation_scene
    azure_request
  end

  describe "POST /internal/mpt/tts_fallback" do
    it "returns WAV audio for an authenticated approved scene" do
      post "/internal/mpt/tts_fallback",
           params: raw_body,
           headers: {
             "CONTENT_TYPE" => "application/json",
             "X-MPT-Timestamp" => timestamp,
             "X-MPT-Signature" => signature
           }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("audio/wav")
      expect(response.body).to eq(azure_audio)
    end

    it "rejects an invalid signature without calling Azure" do
      post "/internal/mpt/tts_fallback",
           params: raw_body,
           headers: {
             "CONTENT_TYPE" => "application/json",
             "X-MPT-Timestamp" => timestamp,
             "X-MPT-Signature" => "invalid-signature"
           }

      expect(response).to have_http_status(:unprocessable_content)
      expect(workflow_run.outbound_attempts).to be_empty
      expect(azure_request).not_to have_been_requested
    end
  end
end
