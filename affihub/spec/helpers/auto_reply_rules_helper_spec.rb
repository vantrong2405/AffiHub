require "rails_helper"

RSpec.describe AutoReplyRulesHelper, type: :helper do
  describe "#auto_reply_rule_type_options" do
    it "returns the default and keyword choices in workflow order" do
      expect(helper.auto_reply_rule_type_options).to eq(
        [ [ "Câu trả lời mặc định", "default" ], [ "Theo từ khóa", "keyword" ] ]
      )
    end
  end

  describe "#auto_reply_destination_label" do
    it "returns the provider and destination name" do
      social_destination = build(:social_destination, name: "Page Bếp Nhà")

      expect(helper.auto_reply_destination_label(social_destination)).to eq("Facebook · Page Bếp Nhà")
    end
  end

  describe "#auto_reply_destination_options" do
    it "returns each destination label paired with its record id" do
      social_destination = build_stubbed(:social_destination, id: 17, name: "Page Bếp Nhà")

      expect(helper.auto_reply_destination_options([ social_destination ])).to eq(
        [ [ "Facebook · Page Bếp Nhà", 17 ] ]
      )
    end
  end

  describe "#auto_reply_rule_keyword_present?" do
    it "returns true when a rule has a keyword" do
      auto_reply_rule = build(:auto_reply_rule, rule_type: "keyword", keyword: "bếp")

      expect(helper.auto_reply_rule_keyword_present?(auto_reply_rule)).to eq(true)
    end

    it "returns false when a rule has no keyword" do
      auto_reply_rule = build(:auto_reply_rule, rule_type: "default", keyword: nil)

      expect(helper.auto_reply_rule_keyword_present?(auto_reply_rule)).to eq(false)
    end
  end

  describe "#auto_reply_rule_status_label" do
    it "returns the enabled state" do
      auto_reply_rule = build(:auto_reply_rule, enabled: true)

      expect(helper.auto_reply_rule_status_label(auto_reply_rule)).to eq("Đang bật")
    end

    it "returns the disabled state" do
      auto_reply_rule = build(:auto_reply_rule, enabled: false)

      expect(helper.auto_reply_rule_status_label(auto_reply_rule)).to eq("Đã tắt")
    end
  end
end
