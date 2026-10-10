require "rails_helper"

RSpec.describe "Auto-reply rules", type: :request do
  describe "GET /auto_reply_rules" do
    it "returns the rule list" do
      get auto_reply_rules_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /auto_reply_rules/new" do
    it "returns the rule form with connected comment destinations" do
      create(:social_destination, name: "Page Bếp Nhà")

      get new_auto_reply_rule_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /auto_reply_rules/:id" do
    it "returns the selected rule" do
      auto_reply_rule = create(:auto_reply_rule)

      get auto_reply_rule_path(auto_reply_rule)

      expect(response).to have_http_status(:ok)
    end

    it "returns not found when the rule does not exist" do
      get auto_reply_rule_path(id: 99_999_999)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /auto_reply_rules/:id/edit" do
    it "returns the selected rule for editing" do
      auto_reply_rule = create(:auto_reply_rule)

      get edit_auto_reply_rule_path(auto_reply_rule)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /auto_reply_rules" do
    it "persists a normalized keyword rule without an external subscription request" do
      social_destination = create(:social_destination)

      expect do
        post auto_reply_rules_path, params: {
          auto_reply_rule: {
            social_destination_id: social_destination.id,
            rule_type: "keyword",
            keyword: "  MUA NGAY  ",
            reply_text: "Bạn có thể đặt hàng tại cửa hàng của chúng tôi.",
            enabled: "1"
          }
        }
      end.to change(AutoReplyRule, :count).by(1)

      auto_reply_rule = AutoReplyRule.order(:id).last
      expect(response).to redirect_to(auto_reply_rule_path(auto_reply_rule))
      expect(auto_reply_rule.keyword).to eq("mua ngay")
      expect(auto_reply_rule.enabled?).to eq(true)
    end

    it "rejects a second default rule for the same destination" do
      social_destination = create(:social_destination)
      create(:auto_reply_rule, social_destination:, rule_type: "default")

      expect do
        post auto_reply_rules_path, params: {
          auto_reply_rule: {
            social_destination_id: social_destination.id,
            rule_type: "default",
            reply_text: "Câu trả lời thứ hai",
            enabled: "1"
          }
        }
      end.not_to change(AutoReplyRule, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /auto_reply_rules/:id" do
    it "returns not found when the rule does not exist" do
      patch auto_reply_rule_path(id: 99_999_999), params: {
        auto_reply_rule: { reply_text: "Nội dung cập nhật" }
      }

      expect(response).to have_http_status(:not_found)
    end

    it "persists an edited keyword response" do
      auto_reply_rule = create(:auto_reply_rule, rule_type: "keyword", keyword: "giao hàng")

      patch auto_reply_rule_path(auto_reply_rule), params: {
        auto_reply_rule: { keyword: "ship hàng", reply_text: "Phí ship được miễn phí hôm nay." }
      }

      expect(response).to redirect_to(auto_reply_rule_path(auto_reply_rule))
      expect(auto_reply_rule.reload.keyword).to eq("ship hàng")
      expect(auto_reply_rule.reply_text).to eq("Phí ship được miễn phí hôm nay.")
    end
  end

  describe "DELETE /auto_reply_rules/:id" do
    it "returns not found when the rule does not exist" do
      delete auto_reply_rule_path(id: 99_999_999)

      expect(response).to have_http_status(:not_found)
    end

    it "removes the selected keyword rule" do
      auto_reply_rule = create(:auto_reply_rule, rule_type: "keyword", keyword: "giao hàng")

      expect do
        delete auto_reply_rule_path(auto_reply_rule)
      end.to change(AutoReplyRule, :count).by(-1)

      expect(response).to redirect_to(auto_reply_rules_path)
    end
  end
end
