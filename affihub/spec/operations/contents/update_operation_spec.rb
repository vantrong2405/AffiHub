# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contents::UpdateOperation do
  let(:user) { create(:user) }
  let(:product) { create(:product, user: user, affiliate_url: "https://affiliate.example/original") }
  let(:content) do
    create(
      :content,
      product: product,
      user: user,
      status: "review",
      body: "Original copy",
      affiliate_url: product.affiliate_url
    )
  end

  it "updates only the body while preserving product and affiliate URL" do
    other_product = create(:product, affiliate_url: "https://affiliate.example/attacker")

    operation = described_class.call(
      params: {
        current_user: user,
        id: content.id,
        body: "Edited copy",
        product_id: other_product.id,
        affiliate_url: "https://attacker.example/replace"
      }
    )

    expect(operation.success?).to eq(true)
    expect(content.reload).to have_attributes(
      body: "Edited copy",
      product_id: product.id,
      affiliate_url: "https://affiliate.example/original",
      status: "review"
    )
  end

  it "does not update content that is not under review" do
    content.update!(status: "approved")

    operation = described_class.call(params: { current_user: user, id: content.id, body: "Changed copy" })

    expect(operation.success?).to eq(false)
    expect(content.reload.body).to eq("Original copy")
  end

  it "does not expose content owned by another user" do
    other_user = create(:user)
    other_content = create(:content, user: other_user, status: "review", body: "Private copy")

    operation = described_class.call(params: { current_user: user, id: other_content.id, body: "Changed copy" })

    expect(operation.success?).to eq(false)
    expect(operation.errors.full_messages.to_sentence).to eq("Content không tồn tại hoặc không thuộc tài khoản của bạn")
    expect(other_content.reload.body).to eq("Private copy")
  end
end
