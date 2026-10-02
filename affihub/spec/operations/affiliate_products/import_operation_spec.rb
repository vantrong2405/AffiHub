# frozen_string_literal: true

require "rails_helper"
require "csv"
require "stringio"

RSpec.describe AffiliateProducts::ImportOperation do
  let(:user) { create(:user) }
  let!(:connection) { create(:affiliate_connection, user: user, provider: "accesstrade", api_key: "accesstrade-token") }
  let(:headers) { %w[idx name url price rating sold discount is_mall location is_ad image] }

  def uploaded_csv(rows, filename: "products.csv")
    content = CSV.generate do |csv|
      csv << headers
      rows.each { |row| csv << row }
    end
    ActionDispatch::Http::UploadedFile.new(
      tempfile: StringIO.new(content),
      filename: filename,
      type: "text/csv"
    )
  end

  def stub_accesstrade_links(urls, links: nil)
    config = Rails.application.config_for(:accesstrade)
    endpoint = URI.join(config.base_url, config.link_path).to_s
    links ||= urls.map do |url|
      { url_origin: url, aff_link: "https://accesstrade.vn/#{url.split('-').last}", short_link: "https://s.net/#{url.split('-').last}" }
    end
    stub_request(:post, endpoint)
      .with(headers: { "Authorization" => "Token accesstrade-token" })
      .to_return(
        status: 200,
        body: { data: { success_link: links, error_link: [], suspend_url: [] } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  describe "#call" do
    it "returns the configured niche keywords, category rules, and filter defaults" do
      config = Rails.application.config_for(:product_catalog)

      expect(config.filters.fetch(:require_keywords)).to eq([ "yến mạch", "yen mach", "oat", "oats", "quaker" ])
      expect(config.filters.fetch(:exclude_ads)).to eq(true)
      expect(config.categories.map { |category| category.fetch(:id) }).to eq(%w[A B])
      expect(config.csv_max_bytes).to eq(10.megabytes)
    end

    it "returns filtered products with categories assigned after category exclusions" do
      pure_oat_url = "https://shopee.vn/oat-pure"
      granola_mix_url = "https://shopee.vn/oat-granola"
      stub_accesstrade_links([ pure_oat_url, granola_mix_url ])
      file = uploaded_csv([
        [ "1", "Yến mạch nguyên chất", pure_oat_url, "59.000", "4.8", "1.5k", "20", "1", "", "0", "" ],
        [ "2", "Yến mạch mix granola", granola_mix_url, "69.000", "4.5", "500", "10", "0", "", "0", "" ],
        [ "3", "Yến mạch rating thấp", "https://shopee.vn/low-rating", "30.000", "3.2", "500", "0", "0", "", "0", "" ],
        [ "4", "Yến mạch quảng cáo", "https://shopee.vn/ad-product", "30.000", "4.5", "500", "0", "0", "", "1", "" ]
      ])

      operation = described_class.call(params: { current_user: user, file: file })

      expect(operation.success?).to be(true)
      expect(Product.where(user: user).order(:title).pluck(:title, :category)).to eq(
        [ [ "Yến mạch mix granola", "B" ], [ "Yến mạch nguyên chất", "A" ] ]
      )
      expect(a_request(:post, %r{api\.accesstrade\.vn}).with do |request|
        JSON.parse(request.body).fetch("urls") == [ pure_oat_url, granola_mix_url ]
      end).to have_been_made.once
    end

    it "returns two normalized products with affiliate links mapped to their source URLs" do
      first_url = "https://shopee.vn/product-a"
      second_url = "https://shopee.vn/product-b"
      stub_accesstrade_links(
        [ first_url, second_url ],
        links: [
          { url_origin: second_url, aff_link: "https://accesstrade.vn/b", short_link: "https://s.net/b" },
          { url_origin: first_url, aff_link: "https://accesstrade.vn/a", short_link: "https://s.net/a" }
        ]
      )
      file = uploaded_csv([
        [ "1", "Yến mạch Product A", first_url, "59.000", "4.8", "1.5k", "20", "1", "Hồ Chí Minh", "0", "https://img.test/a.jpg" ],
        [ "2", "Oat Product B", second_url, "120.000", "4.5", "10k+", "15", "0", "Hà Nội", "0", "https://img.test/b.jpg" ],
        [ "3", "Duplicate Yến mạch Product A", first_url, "59.000", "4.8", "1.5k", "20", "1", "Hồ Chí Minh", "0", "" ]
      ])

      operation = described_class.call(params: { current_user: user, file: file })

      expect(operation.success?).to be(true)
      expect(operation.imported_count).to eq(2)
      expect(Product.where(user: user).order(:title).pluck(:title, :price, :rating, :sold, :discount, :is_mall, :original_product_url, :affiliate_url)).to eq(
        [
          [ "Oat Product B", 120_000, 4.5, 10_000, 15, false, second_url, "https://accesstrade.vn/b" ],
          [ "Yến mạch Product A", 59_000, 4.8, 1_500, 20, true, first_url, "https://accesstrade.vn/a" ]
        ]
      )
      expect(Product.find_by!(user: user, original_product_url: first_url).raw_source_data).to include("\"name\":\"Yến mạch Product A\"")
      expect(Product.find_by!(user: user, original_product_url: first_url).last_synced_at).to be_present
      expect(a_request(:post, URI.join(Rails.application.config_for(:accesstrade).base_url, Rails.application.config_for(:accesstrade).link_path).to_s)
        .with { |request| JSON.parse(request.body).fetch("urls") == [ second_url, first_url ] }).to have_been_made.once
    end

    it "returns a file error without calling ACCESSTRADE when required CSV headers are missing" do
      file = ActionDispatch::Http::UploadedFile.new(
        tempfile: StringIO.new("name,url\nProduct,https://shopee.vn/product-a\n"),
        filename: "products.csv",
        type: "text/csv"
      )

      operation = described_class.call(params: { current_user: user, file: file })

      expect(operation.success?).to be(false)
      expect(operation.errors).to be_present
      expect(Product.where(user: user)).to be_empty
      expect(WebMock).not_to have_requested(:post, %r{api\.accesstrade\.vn})
    end

    it "returns a file error without calling ACCESSTRADE when CSV cannot be parsed" do
      file = ActionDispatch::Http::UploadedFile.new(
        tempfile: StringIO.new("\"unterminated,field\n"),
        filename: "products.csv",
        type: "text/csv"
      )

      operation = described_class.call(params: { current_user: user, file: file })

      expect(operation.success?).to be(false)
      expect(operation.errors).to be_present
      expect(Product.where(user: user)).to be_empty
      expect(WebMock).not_to have_requested(:post, %r{api\.accesstrade\.vn})
    end

    it "returns one imported product while rejecting unsafe URLs before the ACCESSTRADE request" do
      valid_url = "https://shopee.vn/product-a"
      stub_accesstrade_links([ valid_url ])
      file = uploaded_csv([
        [ "1", "Valid oat product", valid_url, "59.000", "4.8", "1.5k", "20", "1", "Hồ Chí Minh", "0", "" ],
        [ "2", "External product", "https://example.com/product", "20.000", "4.0", "10", "0", "0", "Hà Nội", "0", "" ]
      ])

      operation = described_class.call(params: { current_user: user, file: file })

      expect(operation.success?).to be(true)
      expect(operation.imported_count).to eq(1)
      expect(operation.failed_count).to eq(1)
      expect(Product.where(user: user).pluck(:original_product_url, :affiliate_url)).to eq(
        [ [ valid_url, "https://accesstrade.vn/a" ] ]
      )
      expect(a_request(:post, %r{api\.accesstrade\.vn}).with { |request| JSON.parse(request.body).fetch("urls") == [ valid_url ] })
        .to have_been_made.once
    end

    it "updates the current user's product on re-import while preserving another user's product" do
      url = "https://shopee.vn/product-a"
      other_user = create(:user)
      create(:affiliate_connection, user: other_user, provider: "accesstrade", api_key: "other-token")
      existing = create(:product, user: user, affiliate_provider: "accesstrade", original_product_url: url, title: "Old title")
      other_product = create(:product, user: other_user, affiliate_provider: "accesstrade", original_product_url: url, title: "Other user's title")
      [ "Updated title", "Newest title" ].each_with_index do |title, index|
        stub_accesstrade_links(
          [ url ],
          links: [ { url_origin: url, aff_link: "https://accesstrade.vn/#{index}", short_link: "https://s.net/#{index}" } ]
        )
        operation = described_class.call(
          params: {
            current_user: user,
            file: uploaded_csv([ [ "1", "Yến mạch #{title}", url, "59.000", "4.8", "1.5k", "20", "1", "Hồ Chí Minh", "0", "" ] ])
          }
        )

        expect(operation.success?).to be(true)
      end

      expect(Product.where(user: user, original_product_url: url).count).to eq(1)
      expect(existing.reload.title).to eq("Yến mạch Newest title")
      expect(existing.affiliate_url).to eq("https://accesstrade.vn/1")
      expect(other_product.reload.title).to eq("Other user's title")
      expect(Product.where(user: other_user, original_product_url: url).count).to eq(1)
    end

    it "returns accurate success and failure counts for ACCESSTRADE errors and unmapped URLs" do
      success_url = "https://shopee.vn/product-a"
      rejected_url = "https://shopee.vn/product-b"
      unmapped_url = "https://shopee.vn/product-c"
      stub_accesstrade_links(
        [ success_url, rejected_url, unmapped_url ],
        links: [ { url_origin: success_url, aff_link: "https://accesstrade.vn/a", short_link: "https://s.net/a" } ]
      )
      stub_request(:post, URI.join(Rails.application.config_for(:accesstrade).base_url, Rails.application.config_for(:accesstrade).link_path).to_s)
        .with { |request| JSON.parse(request.body).fetch("urls").include?(success_url) }
        .to_return(
          status: 200,
          body: {
            data: {
              success_link: [ { url_origin: success_url, aff_link: "https://accesstrade.vn/a", short_link: "https://s.net/a" } ],
              error_link: [ { url_origin: rejected_url, error: "invalid_url" } ],
              suspend_url: [ unmapped_url ]
            }
          }.to_json
        )
      file = uploaded_csv([
        [ "1", "Oat Success", success_url, "1.000", "4.5", "200", "0", "0", "", "0", "" ],
        [ "2", "Oat Rejected", rejected_url, "1.000", "4.5", "200", "0", "0", "", "0", "" ],
        [ "3", "Oat Unmapped", unmapped_url, "1.000", "4.5", "200", "0", "0", "", "0", "" ]
      ])

      operation = described_class.call(params: { current_user: user, file: file })

      expect(operation.success?).to be(true)
      expect(operation.imported_count).to eq(1)
      expect(operation.failed_count).to eq(2)
      expect(Product.where(user: user).pluck(:original_product_url)).to eq([ success_url ])
    end
  end
end
