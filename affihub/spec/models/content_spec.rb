# frozen_string_literal: true

require "rails_helper"

RSpec.describe Content, type: :model do
  subject(:content) { build(:content) }

  it "returns true for valid? with a product, user and required attributes" do
    expect(content.valid?).to eq(true)
  end

  it "belongs to a product" do
    expect(Content.reflect_on_association(:product).macro).to eq(:belongs_to)
  end

  it "belongs to a user" do
    expect(Content.reflect_on_association(:user).macro).to eq(:belongs_to)
  end

  it "allows a product to have many contents" do
    expect(Product.reflect_on_association(:contents).macro).to eq(:has_many)
  end

  it "returns 'generated' as a valid status enum value" do
    content.status = "generated"
    expect(content.valid?).to eq(true)
  end

  it "returns 'review' as a valid status enum value" do
    content.status = "review"
    expect(content.valid?).to eq(true)
  end

  it "returns 'approved' as a valid status enum value" do
    content.status = "approved"
    expect(content.valid?).to eq(true)
  end

  it "stores all generated copy in one text body column" do
    expect(Content.columns_hash.fetch("body").type).to eq(:text)
    expect(Content.column_names & %w[hook caption cta hashtags]).to eq([])
  end

  it "defaults generation_count to zero" do
    expect(Content.new.generation_count).to eq(0)
    expect(Content.columns_hash.fetch("generation_count").type).to eq(:integer)
    expect(Content.columns_hash.fetch("generation_count").null).to eq(false)
  end

  it "allows multiple contents for one product with a non-unique index" do
    product_index = Content.connection.indexes(:contents).find { |index| index.columns == [ "product_id" ] }

    expect(product_index&.unique).to eq(false)
  end

  describe "#start_review!" do
    it "transitions a generated content to review" do
      content = create(:content, status: "generated")

      expect(content.start_review!).to eq(true)
      expect(content.status).to eq("review")
    end

    it "returns rejected content to review" do
      content = create(:content, status: "rejected")

      expect(content.start_review!).to eq(true)
      expect(content.reload.status).to eq("review")
    end

    it "raises when the content is neither generated nor rejected" do
      content = create(:content, status: "review")

      expect { content.start_review! }.to raise_error(Content::InvalidTransitionError)
      expect(content.status).to eq("review")
    end
  end

  describe "#approve! and #reject!" do
    it "approves review content" do
      content = create(:content, status: "review")

      expect(content.approve!).to eq(true)
      expect(content.reload.status).to eq("approved")
    end

    it "rejects review content" do
      content = create(:content, status: "review")

      expect(content.reject!).to eq(true)
      expect(content.reload.status).to eq("rejected")
    end

    %w[generated approved rejected].each do |status|
      it "raises when asked to approve or reject content in #{status}" do
        content = create(:content, status: status)

        expect { content.approve! }.to raise_error(Content::InvalidTransitionError)
        expect { content.reject! }.to raise_error(Content::InvalidTransitionError)
        expect(content.reload.status).to eq(status)
      end
    end
  end
end
