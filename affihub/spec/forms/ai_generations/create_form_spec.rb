# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::CreateForm, type: :form do
  let(:form_attributes) do
    {
      topic: "Summer skincare",
      language: "vi",
      tone: "friendly",
      target_duration: 30,
      ai_provider_connection_id: 1
    }
  end
  subject(:form) { described_class.new(form_attributes) }

  describe "validations" do
    it "returns valid when all required inputs are present" do
      expect(form).to be_valid
    end

    context "when an AI provider connection is missing" do
      let(:form_attributes) { super().except(:ai_provider_connection_id) }

      it "returns invalid" do
        expect(form).not_to be_valid
      end
    end

    context "when topic is blank" do
      let(:form_attributes) { super().merge(topic: " ") }

      it "returns invalid" do
        expect(form).not_to be_valid
      end
    end

    context "when language is blank" do
      let(:form_attributes) { super().merge(language: nil) }

      it "returns invalid" do
        expect(form).not_to be_valid
      end
    end

    context "when tone is blank" do
      let(:form_attributes) { super().merge(tone: " ") }

      it "returns invalid" do
        expect(form).not_to be_valid
      end
    end

    context "when target duration is blank" do
      let(:form_attributes) { super().merge(target_duration: nil) }

      it "returns invalid" do
        expect(form).not_to be_valid
      end
    end

    context "when target duration is zero" do
      let(:form_attributes) { super().merge(target_duration: 0) }

      it "returns invalid" do
        expect(form).not_to be_valid
      end
    end

    context "when scene duration is below three seconds" do
      let(:form_attributes) { super().merge(scene_duration: 2) }

      it "returns invalid" do
        expect(form).not_to be_valid
      end
    end

    context "when scene duration is above twelve seconds" do
      let(:form_attributes) { super().merge(scene_duration: 13) }

      it "returns invalid" do
        expect(form).not_to be_valid
      end
    end

    context "when scene count is zero" do
      let(:form_attributes) { super().merge(scene_count: 0) }

      it "returns invalid" do
        expect(form).not_to be_valid
      end
    end
  end

  describe "defaults" do
    it "returns the standard text to video profile" do
      expect(form.attributes.slice(:model_id, :resolution, :scene_count, :scene_duration)).to eq(
        model_id: "seedance-lite-t2v",
        resolution: "480p",
        scene_count: 5,
        scene_duration: 6
      )
    end
  end
end
