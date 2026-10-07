require "rails_helper"

RSpec.describe "AiGenerations::CreateForm", type: :form do
  let(:form_attributes) do
    {
      topic: "Summer skincare",
      language: "vi",
      tone: "friendly",
      target_duration: 30
    }
  end

  describe "validations" do
    it "returns valid when all required inputs are present" do
      form = "AiGenerations::CreateForm".constantize.new(form_attributes)

      expect(form).to be_valid
    end

    it "returns invalid when topic is blank" do
      form = "AiGenerations::CreateForm".constantize.new(form_attributes.merge(topic: " "))

      expect(form).not_to be_valid
    end

    it "returns invalid when language is blank" do
      form = "AiGenerations::CreateForm".constantize.new(form_attributes.merge(language: nil))

      expect(form).not_to be_valid
    end

    it "returns invalid when tone is blank" do
      form = "AiGenerations::CreateForm".constantize.new(form_attributes.merge(tone: " "))

      expect(form).not_to be_valid
    end

    it "returns invalid when target duration is blank" do
      form = "AiGenerations::CreateForm".constantize.new(form_attributes.merge(target_duration: nil))

      expect(form).not_to be_valid
    end

    it "returns invalid when target duration is zero" do
      form = "AiGenerations::CreateForm".constantize.new(form_attributes.merge(target_duration: 0))

      expect(form).not_to be_valid
    end

    it "returns invalid when scene duration is below three seconds" do
      form = "AiGenerations::CreateForm".constantize.new(form_attributes.merge(scene_duration: 2))

      expect(form).not_to be_valid
    end

    it "returns invalid when scene duration is above twelve seconds" do
      form = "AiGenerations::CreateForm".constantize.new(form_attributes.merge(scene_duration: 13))

      expect(form).not_to be_valid
    end

    it "returns invalid when scene count is zero" do
      form = "AiGenerations::CreateForm".constantize.new(form_attributes.merge(scene_count: 0))

      expect(form).not_to be_valid
    end
  end

  describe "defaults" do
    it "returns the standard text to video profile" do
      form = "AiGenerations::CreateForm".constantize.new(form_attributes)

      expect(form.attributes.slice(:model_id, :resolution, :scene_count, :scene_duration)).to eq(
        model_id: "seedance-lite-t2v",
        resolution: "480p",
        scene_count: 5,
        scene_duration: 6
      )
    end
  end
end
