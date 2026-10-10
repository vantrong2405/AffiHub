# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::NewService, type: :service do
  let(:video_project) { create(:video_project) }
  let(:service) { described_class.new(video_project_id: video_project.id) }
  let(:generation_profile) do
    Rails.application.config_for(:money_printer_turbo).deep_symbolize_keys.fetch(:generation_profile)
  end

  describe "#call" do
    it "returns the selected video project" do
      service.call

      expect(service.video_project).to eq(video_project)
    end

    it "returns the configured generation defaults" do
      service.call

      expect(service.create_form.attributes.slice(:model_id, :resolution, :scene_count, :scene_duration)).to eq(
        generation_profile.slice(:model_id, :resolution, :scene_count, :scene_duration)
      )
    end

    it "returns no accounts while inference capabilities remain disabled" do
      ready_connection = create(:ai_provider_connection, status: :ready)
      create(:ai_provider_connection, status: :ready, selected_model: nil)
      create(:ai_provider_connection, status: :pending_verification)
      create(
        :ai_provider_connection,
        provider: "gemini",
        provider_client_id: "gemini-web-client",
        status: :pending_verification
      )

      service.call

      expect(ready_connection.provider).to eq("gemini")
      expect(service.ai_provider_connections).to eq([])
      expect(service.create_form.ai_provider_connection_id).to eq(nil)
    end
  end
end
