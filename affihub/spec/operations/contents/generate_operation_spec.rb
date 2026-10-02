# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contents::GenerateOperation do
  let(:user) { create(:user) }
  let(:product) do
    create(
      :product,
      user: user,
      title: "Oat Drink",
      description: "Unsweetened oats",
      price: 59_000,
      original_price: 79_000,
      discount: 25,
      rating: 4.8,
      sold: 1_500,
      affiliate_url: "https://affiliate.example/product-a"
    )
  end
  let(:connection) do
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

  it "creates a new review content with the product facts and app-owned affiliate URL" do
    connection
    prompt_request = stub_codex_response("Fresh oat copy")

    operation = described_class.call(params: { current_user: user, product_id: product.id, tone: "friendly" })

    expect(operation.success?).to eq(true)
    expect(operation.content).to have_attributes(
      product_id: product.id,
      user_id: user.id,
      status: "review",
      body: "Fresh oat copy",
      affiliate_url: "https://affiliate.example/product-a"
    )
    expect(prompt_request).to have_been_requested.once
  end

  it "returns an ownership error without exposing another user's product facts to the provider" do
    other_product = create(:product, title: "Private product facts")
    request = stub_request(:post, CodexClient::CONFIG.responses_url)

    operation = described_class.call(params: { current_user: user, product_id: other_product.id })

    expect(operation.success?).to eq(false)
    expect(operation.errors.full_messages.to_sentence).to eq("Product không tồn tại hoặc không thuộc tài khoản của bạn")
    expect(Content.count).to eq(0)
    expect(request).not_to have_been_requested
  end

  it "creates another content row when the product already has an approved content" do
    connection
    approved_content = create(:content, product: product, user: user, status: "approved", body: "Approved copy")
    stub_codex_response("A second draft")

    operation = described_class.call(params: { current_user: user, product_id: product.id })

    expect(operation.success?).to eq(true)
    expect(Product.find(product.id).contents.order(:id).pluck(:id, :body, :status)).to eq(
      [ [ approved_content.id, "Approved copy", "approved" ], [ operation.content.id, "A second draft", "review" ] ]
    )
    expect(operation.content.id).not_to eq(approved_content.id)
  end

  it "keeps an AI-generated URL out of the copy and attaches the product affiliate URL" do
    connection
    stub_codex_response("Try this offer at https://untrusted.example/promo. Product facts stay unchanged.")

    operation = described_class.call(params: { current_user: user, product_id: product.id })

    expect(operation.success?).to eq(true)
    expect(operation.content.body).to eq("Try this offer at Product facts stay unchanged.")
    expect(operation.content.affiliate_url).to eq(product.affiliate_url)
    expect(product.reload.affiliate_url).to eq("https://affiliate.example/product-a")
  end

  it "returns a reconnect message without creating content for a disconnected AI connection" do
    create(:ai_connection, user: user, status: "disconnected")
    request = stub_request(:post, CodexClient::CONFIG.responses_url)

    operation = described_class.call(params: { current_user: user, product_id: product.id })

    expect(operation.success?).to eq(false)
    expect(operation.errors.full_messages.to_sentence).to eq("AI connection đã mất kết nối, cần kết nối lại")
    expect(Content.count).to eq(0)
    expect(request).not_to have_been_requested
  end

  it "returns a retry message without creating content when the provider request times out" do
    connection
    stub_request(:post, CodexClient::CONFIG.responses_url).to_timeout

    operation = described_class.call(params: { current_user: user, product_id: product.id })

    expect(operation.success?).to eq(false)
    expect(operation.errors.full_messages.to_sentence).to eq("Không thể kết nối tới AI provider lúc này. Vui lòng thử lại")
    expect(Content.count).to eq(0)
  end
end
