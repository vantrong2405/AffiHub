require "rails_helper"

RSpec.describe "AutoResponder::SelectRuleService", type: :service do
  describe "#call" do
    let(:destination) { create(:social_destination, provider: "facebook") }
    let(:default_rule) do
      AutoReplyRule.create!(
        social_destination: destination,
        rule_type: "default",
        reply_text: "Cảm ơn bạn đã quan tâm."
      )
    end

    it "returns the default response when no active keyword matches" do
      default_rule
      AutoReplyRule.create!(
        social_destination: destination,
        rule_type: "keyword",
        keyword: "vận chuyển",
        reply_text: "Phí vận chuyển được tính theo khu vực."
      )
      service = AutoResponder::SelectRuleService.new(
        social_destination_id: destination.id,
        comment_text: "Mẫu này còn hàng không?"
      )

      expect(service.call).to eq(true)
      expect(service.rule).to eq(default_rule)
      expect(service.reply_text).to eq("Cảm ơn bạn đã quan tâm.")
    end

    it "returns the static reply for an active matching keyword" do
      default_rule
      keyword_rule = AutoReplyRule.create!(
        social_destination: destination,
        rule_type: "keyword",
        keyword: "vận chuyển",
        reply_text: "Phí vận chuyển được tính theo khu vực."
      )
      service = AutoResponder::SelectRuleService.new(
        social_destination_id: destination.id,
        comment_text: "Cho mình hỏi phí vận chuyển"
      )

      expect(service.call).to eq(true)
      expect(service.rule).to eq(keyword_rule)
      expect(service.reply_text).to eq("Phí vận chuyển được tính theo khu vực.")
    end

    it "returns the default response when a matching keyword rule is disabled" do
      default_rule
      AutoReplyRule.create!(
        social_destination: destination,
        rule_type: "keyword",
        keyword: "vận chuyển",
        reply_text: "Phí vận chuyển được tính theo khu vực.",
        enabled: false
      )
      service = AutoResponder::SelectRuleService.new(
        social_destination_id: destination.id,
        comment_text: "Cho mình hỏi phí vận chuyển"
      )

      expect(service.call).to eq(true)
      expect(service.rule).to eq(default_rule)
      expect(service.reply_text).to eq("Cảm ơn bạn đã quan tâm.")
    end

    it "returns the response for the longest matching keyword" do
      default_rule
      AutoReplyRule.create!(
        social_destination: destination,
        rule_type: "keyword",
        keyword: "giao hang",
        reply_text: "Thông tin giao hàng chung."
      )
      longest_keyword_rule = AutoReplyRule.create!(
        social_destination: destination,
        rule_type: "keyword",
        keyword: "giao hang nhanh",
        reply_text: "Đơn giao nhanh đến trong ngày."
      )
      service = described_class.new(
        social_destination_id: destination.id,
        comment_text: "Mình muốn chọn giao hang nhanh."
      )

      expect(service.call).to eq(true)
      expect(service.rule).to eq(longest_keyword_rule)
      expect(service.reply_text).to eq("Đơn giao nhanh đến trong ngày.")
    end

    it "returns the response for the earliest created rule when matching keyword lengths are equal" do
      default_rule
      earliest_keyword_rule = AutoReplyRule.create!(
        social_destination: destination,
        rule_type: "keyword",
        keyword: "ho tro",
        reply_text: "Hỗ trợ câu một."
      )
      AutoReplyRule.create!(
        social_destination: destination,
        rule_type: "keyword",
        keyword: "tro ho",
        reply_text: "Hỗ trợ câu hai."
      )
      service = described_class.new(
        social_destination_id: destination.id,
        comment_text: "ho tro và tro ho"
      )

      expect(service.call).to eq(true)
      expect(service.rule).to eq(earliest_keyword_rule)
      expect(service.reply_text).to eq("Hỗ trợ câu một.")
    end
  end
end
