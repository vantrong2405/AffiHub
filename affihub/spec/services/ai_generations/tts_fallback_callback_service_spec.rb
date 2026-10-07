# frozen_string_literal: true

require "rails_helper"
require "openssl"

RSpec.describe AiGenerations::TtsFallbackCallbackService, type: :service do
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
    {
      confirmed: true,
      confirmed_at: 1.minute.ago.iso8601,
      estimate: estimate_snapshot
    }
  end
  let(:video_project) { create(:video_project) }
  let(:ai_generation) do
    create(
      :ai_generation,
      video_project:,
      status: "processing",
      estimate_snapshot: { currency: "USD" }
    )
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
  let(:request_payload) do
    {
      correlation_id: ai_generation.correlation_id,
      scene_index: ai_generation_scene.scene_index,
      narration:,
      voice:
    }
  end
  let(:raw_body) { request_payload.to_json }
  let(:signature) do
    OpenSSL::HMAC.hexdigest("SHA256", callback_secret, "#{timestamp}.#{raw_body}")
  end
  let(:service) { described_class.new(raw_body:, timestamp:, signature:) }
  let(:replay_service) { described_class.new(raw_body:, timestamp:, signature:) }
  let(:azure_request) do
    stub_request(:post, "https://azure-speech.test/cognitiveservices/v1")
      .to_return(status: 200, body: azure_audio)
  end

  describe "#call" do
    subject(:call_result) { service.call }

    before do
      workflow_run
      ai_generation_scene
      azure_request
    end

    context "when the callback signature is invalid" do
      let(:signature) { "invalid-signature" }

      it "rejects the callback before creating an attempt or calling Azure" do
        call_result

        expect(service).not_to be_success
        expect(workflow_run.outbound_attempts).to be_empty
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when the callback timestamp has expired" do
      let(:timestamp) { 10.minutes.ago.to_i.to_s }

      it "rejects the callback before creating an attempt or calling Azure" do
        call_result

        expect(service).not_to be_success
        expect(workflow_run.outbound_attempts).to be_empty
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when the generation does not exist" do
      let(:request_payload) { super().merge(correlation_id: "missing-generation") }

      it "rejects the callback before calling Azure" do
        call_result

        expect(service).not_to be_success
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when the scene does not belong to the generation" do
      let(:request_payload) { super().merge(scene_index: 1) }

      it "rejects the callback before creating an attempt or calling Azure" do
        call_result

        expect(service).not_to be_success
        expect(workflow_run.outbound_attempts).to be_empty
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when the narration differs from the approved scene" do
      let(:request_payload) { super().merge(narration: "Changed narration.") }

      it "rejects the callback before creating an attempt or calling Azure" do
        call_result

        expect(service).not_to be_success
        expect(workflow_run.outbound_attempts).to be_empty
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when the voice differs from the approved scene" do
      let(:request_payload) { super().merge(voice: "vi-VN-NamMinhNeural") }

      it "rejects the callback before creating an attempt or calling Azure" do
        call_result

        expect(service).not_to be_success
        expect(workflow_run.outbound_attempts).to be_empty
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when the Azure estimate is missing" do
      let(:estimate_snapshot) { {} }

      it "rejects the callback before creating an attempt or calling Azure" do
        call_result

        expect(service).not_to be_success
        expect(workflow_run.outbound_attempts).to be_empty
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when the Azure estimate has expired" do
      let(:estimate_snapshot) { super().merge(estimated_at: 2.hours.ago.iso8601) }

      it "rejects the callback before creating an attempt or calling Azure" do
        call_result

        expect(service).not_to be_success
        expect(workflow_run.outbound_attempts).to be_empty
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when the Azure estimate belongs to different narration" do
      let(:estimate_snapshot) do
        super().merge(input_snapshot: { narration: "Other narration.", voice: })
      end

      it "rejects the callback before creating an attempt or calling Azure" do
        call_result

        expect(service).not_to be_success
        expect(workflow_run.outbound_attempts).to be_empty
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when the Azure estimate belongs to a different voice" do
      let(:estimate_snapshot) do
        super().merge(input_snapshot: { narration:, voice: "vi-VN-NamMinhNeural" })
      end

      it "rejects the callback before creating an attempt or calling Azure" do
        call_result

        expect(service).not_to be_success
        expect(workflow_run.outbound_attempts).to be_empty
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when the estimate is from a different provider" do
      let(:estimate_snapshot) { super().merge(provider: "other_speech") }

      it "rejects the callback before creating an attempt or calling Azure" do
        call_result

        expect(service).not_to be_success
        expect(workflow_run.outbound_attempts).to be_empty
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when the estimate amount is invalid" do
      let(:estimate_snapshot) { super().merge(amount: "not-a-number") }

      it "rejects the callback before creating an attempt or calling Azure" do
        call_result

        expect(service).not_to be_success
        expect(workflow_run.outbound_attempts).to be_empty
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when the estimate currency differs from the generation estimate" do
      let(:estimate_snapshot) { super().merge(currency: "EUR") }

      it "rejects the callback before creating an attempt or calling Azure" do
        call_result

        expect(service).not_to be_success
        expect(workflow_run.outbound_attempts).to be_empty
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when Azure cost consent is missing" do
      let(:consent_snapshot) { super().merge(confirmed: false) }

      it "rejects the callback before creating an attempt or calling Azure" do
        call_result

        expect(service).not_to be_success
        expect(workflow_run.outbound_attempts).to be_empty
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when consent refers to a different Azure estimate" do
      let(:consent_snapshot) do
        super().merge(estimate: estimate_snapshot.merge(amount: "0.02"))
      end

      it "rejects the callback before creating an attempt or calling Azure" do
        call_result

        expect(service).not_to be_success
        expect(workflow_run.outbound_attempts).to be_empty
        expect(azure_request).not_to have_been_requested
      end
    end

    context "when the callback matches the approved scene and current consent" do
      it "persists the submitting attempt before calling Azure" do
        attempt_status_at_request = []
        stub_request(:post, "https://azure-speech.test/cognitiveservices/v1")
          .to_return do
            attempt_status_at_request << workflow_run.reload.outbound_attempts.sole.status
            { status: 200, body: azure_audio }
          end

        call_result

        expect(attempt_status_at_request).to eq([ "submitting" ])
      end

      it "returns the Azure WAV for the approved scene" do
        call_result

        expect(service.audio_data).to eq(azure_audio)
      end

      it "attaches the generated WAV to the approved scene" do
        call_result

        expect(ai_generation_scene.reload.voiceover.download).to eq(azure_audio)
      end

      it "marks the scene completed after storing the WAV" do
        call_result

        expect(ai_generation_scene.reload.status).to eq("completed")
      end

      it "keeps the generation processing after completing one scene" do
        call_result

        expect(ai_generation.reload.status).to eq("processing")
      end

      it "confirms the outbound attempt after Azure succeeds" do
        call_result

        expect(workflow_run.outbound_attempts.sole.status).to eq("confirmed")
      end

      it "records Azure Speech and the consented quote on the attempt" do
        call_result

        expect(workflow_run.outbound_attempts.sole.provider_reference).to eq(
          "provider" => "azure_speech",
          "quoted_amount" => "0.01",
          "currency" => "USD",
          "scene_index" => 0
        )
      end

      context "when the callback is replayed" do
        before do
          call_result
          replay_service.call
        end

        it "returns the saved WAV" do
          expect(replay_service.audio_data).to eq(azure_audio)
        end

        it "does not send another Azure request" do
          expect(azure_request).to have_been_requested.once
        end

        it "does not create another outbound attempt" do
          expect(workflow_run.outbound_attempts.count).to eq(1)
        end
      end
    end

    context "when Rails is still waiting for the MPT submission response" do
      let(:ai_generation) do
        create(
          :ai_generation,
          video_project:,
          status: "submitting",
          estimate_snapshot: { currency: "USD" }
        )
      end

      it "accepts the callback for the already saved scene" do
        call_result

        expect(service).to be_success
      end
    end

    context "when Azure times out after receiving the request" do
      let(:azure_request) do
        stub_request(:post, "https://azure-speech.test/cognitiveservices/v1").to_timeout
      end
      let(:replay_service) { described_class.new(raw_body:, timestamp:, signature:) }

      before do
        call_result
        replay_service.call
      end

      it "returns an unsuccessful result" do
        expect(service).not_to be_success
      end

      it "keeps the generation processing while the result is unknown" do
        expect(ai_generation.reload.status).to eq("processing")
      end

      it "marks the scene outcome unknown" do
        expect(ai_generation_scene.reload.status).to eq("outcome_unknown")
      end

      it "marks the outbound attempt outcome unknown" do
        expect(workflow_run.outbound_attempts.sole.status).to eq("outcome_unknown")
      end

      it "does not send Azure another request after a replay" do
        expect(azure_request).to have_been_requested.once
      end
    end
  end
end
