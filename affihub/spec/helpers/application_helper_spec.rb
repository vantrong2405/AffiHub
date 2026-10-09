require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#preflight_status_label" do
    it "returns the Vietnamese label for a passed status" do
      expect(helper.preflight_status_label("passed")).to eq("Đạt")
    end

    it "returns the Vietnamese label for a warning status" do
      expect(helper.preflight_status_label("warning")).to eq("Cảnh báo")
    end

    it "returns the Vietnamese label for a blocked status" do
      expect(helper.preflight_status_label("blocked")).to eq("Chặn")
    end

    it "returns the Vietnamese label for an unavailable status" do
      expect(helper.preflight_status_label("unavailable")).to eq("Chưa thể kiểm tra")
    end

    it "returns the Vietnamese label for a not configured status" do
      expect(helper.preflight_status_label("not_configured")).to eq("Chưa cấu hình")
    end
  end

  describe "#preflight_status_badge_class" do
    it "returns an error badge for a blocked status" do
      expect(helper.preflight_status_badge_class("blocked")).to eq("badge-error")
    end

    it "returns a neutral badge for a not configured status" do
      expect(helper.preflight_status_badge_class("not_configured")).to eq("badge-ghost")
    end
  end
end
