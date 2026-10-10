require "rails_helper"

RSpec.describe "Auto-reply workflow", type: :system do
  it "creates a static keyword rule for a connected comment destination" do
    social_destination = create(:social_destination, name: "Page Bếp Nhà")

    visit auto_reply_rules_path
    click_link "Thêm quy tắc"
    select "Facebook · Page Bếp Nhà", from: "Đích nhận bình luận"
    select "Theo từ khóa", from: "Loại quy tắc"
    fill_in "Từ khóa", with: "  MUA NGAY  "
    fill_in "Câu trả lời", with: "Bạn có thể đặt hàng tại cửa hàng của chúng tôi."
    click_button "Lưu quy tắc"

    expect(page).to have_content("Đã tạo quy tắc tự trả lời.")
    expect(AutoReplyRule.find_by!(social_destination:)).to have_attributes(
      rule_type: "keyword",
      keyword: "mua ngay",
      reply_text: "Bạn có thể đặt hàng tại cửa hàng của chúng tôi."
    )
  end

  it "records a manual confirmation without displaying it as a Meta-confirmed reply" do
    auto_reply_event = create(:auto_reply_event, status: "outcome_unknown")
    workflow_run = create(
      :workflow_run,
      workflowable: auto_reply_event,
      operation: "auto_reply",
      stage: "reply",
      status: "outcome_unknown"
    )
    create(
      :outbound_attempt,
      workflow_run:,
      stage: "reply",
      status: "outcome_unknown",
      sender_stopped_at: 2.minutes.ago,
      request_timeout_at: 1.minute.ago
    )

    visit auto_reply_log_path(auto_reply_event)
    select "Đã xảy ra", from: "Quyết định"
    fill_in "Bằng chứng đối soát", with: "Đã đối chiếu phản hồi trên Meta."
    fill_in "Mã hoặc đường dẫn phản hồi", with: "https://facebook.com/comments/reply-1"
    click_button "Ghi nhận quyết định"

    expect(page).to have_content("Đã lưu quyết định đối soát.")
    expect(page).to have_content("Xác nhận thủ công: đã xảy ra; Meta chưa xác nhận.")
    expect(page).not_to have_content("Đã gửi thành công")
    expect(auto_reply_event.reload.status).to eq("manual_outcome_confirmed")
  end

  it "keeps the entered evidence when a risky retry decision is rejected" do
    auto_reply_event = create(:auto_reply_event, status: "outcome_unknown")
    workflow_run = create(
      :workflow_run,
      workflowable: auto_reply_event,
      operation: "auto_reply",
      stage: "reply",
      status: "outcome_unknown"
    )
    create(
      :outbound_attempt,
      workflow_run:,
      stage: "reply",
      status: "outcome_unknown",
      sender_stopped_at: 2.minutes.ago,
      request_timeout_at: 1.minute.ago
    )

    visit auto_reply_log_path(auto_reply_event)
    select "Chắc chắn chưa xảy ra", from: "Quyết định"
    fill_in "Bằng chứng đối soát", with: "Đã kiểm tra Page, không thấy reply"
    click_button "Ghi nhận quyết định"

    expect(find_field("Quyết định").value).to eq("not_occurred")
    expect(find_field("Bằng chứng đối soát").value).to eq("Đã kiểm tra Page, không thấy reply")
    expect(auto_reply_event.reload.status).to eq("outcome_unknown")
  end
end
