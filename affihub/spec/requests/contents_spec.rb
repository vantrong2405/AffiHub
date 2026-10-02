# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Contents", type: :request do
  let(:user) { create(:user) }
  let(:product) { create(:product, user: user, affiliate_url: "https://s.net/affiliate") }
  let(:ai_connection) { create(:ai_connection, user: user) }

  before { post "/login", params: { email: user.email, password: "password123" } }

  def stub_codex_copy(copy)
    stub_request(:post, CodexClient::CONFIG.responses_url)
      .to_return(
        status: 200,
        body: "data: #{ { type: 'response.output_text.delta', delta: copy }.to_json }\n\ndata: #{ { type: 'response.completed' }.to_json }\n\n",
        headers: { "Content-Type" => "text/event-stream" }
      )
  end

  describe "POST /contents" do
    it "creates a new review Content each time for the same Product" do
      create(:ai_connection, user: user)
      stub_codex_copy("First copy")

      expect do
        post "/contents", params: { product_id: product.id }
      end.to change(Content, :count).by(1)
      first_content = Content.order(:id).last

      stub_codex_copy("Second copy")
      expect do
        post "/contents", params: { product_id: product.id }
      end.to change(Content, :count).by(1)
      second_content = Content.order(:id).last

      expect(response).to redirect_to(content_path(second_content))
      expect(second_content.id).not_to eq(first_content.id)
      expect(second_content.status).to eq("review")
    end

    it "rejects generation for a Product owned by another user" do
      other_product = create(:product)

      post "/contents", params: { product_id: other_product.id }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /contents?product_id=" do
    it "lists all Content rows for the selected Product" do
      first = create(:content, user: user, product: product)
      second = create(:content, user: user, product: product)

      get "/contents", params: { product_id: product.id }

      expect(response).to have_http_status(:ok)
      expect(Content.where(product: product).order(created_at: :desc, id: :desc).pluck(:id)).to eq([ second.id, first.id ])
    end

    it "does not expose a Product owned by another user" do
      get "/contents", params: { product_id: create(:product).id }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /contents/:id" do
    it "renders an owned Content" do
      content = create(:content, user: user, product: product)

      get "/contents/#{content.id}"

      expect(response).to have_http_status(:ok)
    end

    it "does not expose Content owned by another user" do
      content = create(:content)

      get "/contents/#{content.id}"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /contents/:id" do
    it "updates only the selected Content body" do
      content = create(:content, user: user, product: product, status: "review", body: "Before", affiliate_url: product.affiliate_url)
      sibling = create(:content, user: user, product: product, body: "Sibling")

      patch "/contents/#{content.id}", params: { content: { body: "Edited", affiliate_url: "https://evil.test", product_id: create(:product).id } }

      expect(response).to redirect_to(content_path(content))
      expect(content.reload.body).to eq("Edited")
      expect(content.affiliate_url).to eq("https://s.net/affiliate")
      expect(sibling.reload.body).to eq("Sibling")
    end
  end

  describe "POST /contents/:id/approve" do
    it "approves only the selected review Content" do
      content = create(:content, user: user, product: product, status: "review")
      sibling = create(:content, user: user, product: product, status: "review")

      post "/contents/#{content.id}/approve"

      expect(response).to redirect_to(content_path(content))
      expect(content.reload.status).to eq("approved")
      expect(sibling.reload.status).to eq("review")
    end
  end

  describe "POST /contents/:id/reject" do
    it "rejects only the selected review Content" do
      content = create(:content, user: user, product: product, status: "review")
      sibling = create(:content, user: user, product: product, status: "review")

      post "/contents/#{content.id}/reject"

      expect(response).to redirect_to(content_path(content))
      expect(content.reload.status).to eq("rejected")
      expect(sibling.reload.status).to eq("review")
    end
  end

  describe "POST /contents/:id/regenerate" do
    it "regenerates the selected rejected Content in place" do
      create(:ai_connection, user: user)
      content = create(:content, user: user, product: product, status: "rejected", body: "Old", generation_count: 0)
      sibling = create(:content, user: user, product: product, body: "Sibling")
      stub_codex_copy("Replacement")

      expect do
        post "/contents/#{content.id}/regenerate"
      end.not_to change(Content, :count)

      expect(response).to redirect_to(content_path(content))
      expect(content.reload.body).to eq("Replacement")
      expect(content.status).to eq("review")
      expect(content.generation_count).to eq(1)
      expect(sibling.reload.body).to eq("Sibling")
    end
  end
end
