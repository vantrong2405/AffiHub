# frozen_string_literal: true

require "rails_helper"
require "csv"
require "stringio"

RSpec.describe "Products", type: :request do
  let(:user) { create(:user) }
  let!(:connection) { create(:affiliate_connection, user: user, provider: "accesstrade", api_key: "accesstrade-token") }

  before { post "/login", params: { email: user.email, password: "password123" } }

  def uploaded_csv(rows, filename: "products.csv")
    headers = %w[idx name url price rating sold discount is_mall location is_ad image]
    content = CSV.generate do |csv|
      csv << headers
      rows.each { |row| csv << row }
    end
    Rack::Test::UploadedFile.new(StringIO.new(content), "text/csv", true, original_filename: filename)
  end

  def stub_accesstrade_link(url)
    config = Rails.application.config_for(:accesstrade)
    endpoint = URI.join(config.base_url, config.link_path).to_s
    stub_request(:post, endpoint)
      .with(headers: { "Authorization" => "Token accesstrade-token" })
      .to_return(
        status: 200,
        body: { data: { success_link: [ { url_origin: url, aff_link: "https://accesstrade.vn/tracking", short_link: "https://s.net/a" } ] } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  describe "GET /products" do
    it "returns success for the current user's filtered product library" do
      get "/products", params: { category: "A", min_rating: "4.0" }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /products/:id" do
    it "returns success for a product owned by the current user" do
      product = create(:product, user: user, original_product_url: "https://shopee.vn/own")

      get "/products/#{product.id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns not found for a product owned by another user" do
      product = create(:product, original_product_url: "https://shopee.vn/other-user")

      get "/products/#{product.id}"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /products/import" do
    it "imports matching CSV facts and redirects with the imported count" do
      url = "https://shopee.vn/product-import"
      stub_accesstrade_link(url)
      file = uploaded_csv([ [ "1", "Yến mạch nguyên chất", url, "59.000", "4.8", "1.5k", "20", "1", "Hồ Chí Minh", "0", "" ] ])

      post "/products/import", params: { file: file }

      expect(response).to redirect_to(products_path), flash[:alert]
      expect(Product.where(user: user).count).to eq(1)
      expect(flash[:notice]).to include("1")
    end

    it "returns 422 without calling ACCESSTRADE when CSV validation fails" do
      file = Rack::Test::UploadedFile.new(
        StringIO.new("name,url\nInvalid,https://shopee.vn/product\n"), "text/csv", true, original_filename: "products.csv"
      )

      expect do
        post "/products/import", params: { file: file }
      end.not_to change(Product, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(WebMock).not_to have_requested(:post, %r{api\.accesstrade\.vn})
    end

    it "returns 422 without calling ACCESSTRADE when the uploaded file exceeds the configured limit" do
      oversized_file = Rack::Test::UploadedFile.new(
        StringIO.new("x" * (Rails.application.config_for(:product_catalog).csv_max_bytes + 1)),
        "text/csv", true, original_filename: "products.csv"
      )

      expect do
        post "/products/import", params: { file: oversized_file }
      end.not_to change(Product, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(WebMock).not_to have_requested(:post, %r{api\.accesstrade\.vn})
    end
  end
end
