# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contents::RegenerateOperation do
  let(:user) { create(:user) }
  let(:product) { create(:product, user: user, affiliate_url: "https://affiliate.example/original") }
  let(:content) do
    create(
      :content,
      product: product,
      user: user,
      status: "review",
      body: "Original copy",
      affiliate_url: product.affiliate_url,
      generation_count: 0
    )
  end
  let!(:connection) do
    create(
      :ai_connection,
      user: user,
      access_token: "valid-access-token",
      refresh_token: "valid-refresh-token",
      access_token_expires_at: 1.hour.from_now,
      chatgpt_account_id: "account-123"
    )
  end

  def stub_codex_response(text)
    stub_request(:post, CodexClient::CONFIG.responses_url)
      .to_return(
        status: 200,
        body: "data: #{ { type: 'response.output_text.delta', delta: text }.to_json }\n\ndata: #{ { type: 'response.completed' }.to_json }\n\n",
        headers: { "Content-Type" => "text/event-stream" }
      )
  end

  it "updates only the selected review content and increments its generation count" do
    sibling = create(:content, product: product, user: user, status: "review", body: "Sibling copy")
    social_destination = create(:social_destination, social_connection: create(:social_connection, user: user))
    publication = create(:publication, content: sibling, social_destination: social_destination)
    stub_codex_response("Regenerated copy https://untrusted.example/promo")

    operation = described_class.call(params: { current_user: user, id: content.id, tone: "friendly" })

    expect(operation.success?).to eq(true)
    expect(content.reload).to have_attributes(
      id: content.id,
      product_id: product.id,
      body: "Regenerated copy",
      status: "review",
      generation_count: 1,
      affiliate_url: "https://affiliate.example/original"
    )
    expect(sibling.reload).to have_attributes(body: "Sibling copy", status: "review", generation_count: 0)
    expect(publication.reload.content_id).to eq(sibling.id)
  end

  it "returns rejected content to review after regenerating its body" do
    content.update!(status: "rejected")
    stub_codex_response("A new review draft")

    operation = described_class.call(params: { current_user: user, id: content.id })

    expect(operation.success?).to eq(true)
    expect(content.reload).to have_attributes(status: "review", body: "A new review draft", generation_count: 1)
  end

  %w[generated approved].each do |status|
    it "does not regenerate content in #{status}" do
      content.update!(status: status)
      request = stub_request(:post, CodexClient::CONFIG.responses_url)

      operation = described_class.call(params: { current_user: user, id: content.id })

      expect(operation.success?).to eq(false)
      if status == "approved"
        expect(operation.errors.full_messages.to_sentence)
          .to eq("Content đã được approve, không thể regenerate. Hãy tạo Content mới từ Product.")
      end
      expect(content.reload).to have_attributes(body: "Original copy", status: status, generation_count: 0)
      expect(request).not_to have_been_requested
    end
  end

  it "preserves content when the provider request times out" do
    stub_request(:post, CodexClient::CONFIG.responses_url).to_timeout

    operation = described_class.call(params: { current_user: user, id: content.id })

    expect(operation.success?).to eq(false)
    expect(operation.errors.full_messages.to_sentence).to eq("Không thể kết nối tới AI provider lúc này. Vui lòng thử lại")
    expect(content.reload).to have_attributes(body: "Original copy", status: "review", generation_count: 0)
  end

  it "does not regenerate content owned by another user" do
    other_content = create(:content, status: "review", body: "Private copy")
    request = stub_request(:post, CodexClient::CONFIG.responses_url)

    operation = described_class.call(params: { current_user: user, id: other_content.id })

    expect(operation.success?).to eq(false)
    expect(operation.errors.full_messages.to_sentence).to eq("Content không tồn tại hoặc không thuộc tài khoản của bạn")
    expect(other_content.reload.body).to eq("Private copy")
    expect(request).not_to have_been_requested
  end
end
