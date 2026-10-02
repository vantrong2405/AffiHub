# frozen_string_literal: true

require "csv"

class AffiliateProducts::ImportOperation < MainOperation
  extend ActiveModel::Naming
  include ActiveModel::Translation

  CONFIG = Rails.application.config_for(:product_catalog)
  REQUIRED_HEADERS = %w[idx name url price rating sold discount is_mall location is_ad image].freeze

  attr_reader :imported_count, :failed_count

  # @param params [Hash] :current_user and uploaded :file
  # @return [void]
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
    @imported_count = 0
    @failed_count = 0
  end

  # Parses product facts, creates ACCESSTRADE links, and upserts successful products for the user.
  #
  # @return [void]
  def call
    rows = parse_file
    return if error?

    valid_rows, invalid_count = normalize_rows(rows)
    @failed_count += invalid_count
    valid_rows = filter_and_rank(valid_rows)
    return if valid_rows.empty?

    links = AccesstradeClient.new.create_affiliate_links(
      urls: valid_rows.map { |row| row.fetch(:url) },
      token: current_user.affiliate_connection.api_key
    )

    valid_rows.each { |row| persist_product(row, links[row.fetch(:url)]) }
  rescue AccesstradeClient::RequestError => error
    errors.add(:base, "ACCESSTRADE request failed: #{error.message}")
  end

  # Returns a readable value for ActiveModel error messages.
  #
  # @param attribute [Symbol] attribute requested by ActiveModel
  # @return [nil] operations do not expose model attributes
  def read_attribute_for_validation(_attribute)
    nil
  end

  private

  # Reads and validates the CSV structure before any external request or database write.
  #
  # @return [Array<CSV::Row>] parsed data rows
  def parse_file
    file = params[:file]
    return add_file_error("Choose a CSV file to import") unless file.respond_to?(:read)
    return add_file_error("CSV exceeds the #{CONFIG.fetch(:csv_max_bytes)} byte limit") if file.size > CONFIG.fetch(:csv_max_bytes)
    return add_file_error("Upload a .csv file") unless File.extname(file.original_filename).casecmp(".csv").zero?

    content = file.read.force_encoding(Encoding::UTF_8)
    return add_file_error("CSV must use valid UTF-8 text") unless content.valid_encoding?

    csv = CSV.parse(content, headers: true, header_converters: ->(header) { header&.strip })
    headers = csv.headers || []
    missing_headers = REQUIRED_HEADERS - headers
    return add_file_error("CSV is missing required columns: #{missing_headers.join(', ')}") if missing_headers.any?

    csv
  rescue CSV::MalformedCSVError => error
    add_file_error("CSV could not be parsed: #{error.message}")
  end

  # Applies configured product-quality filters, scores and ranks candidates, then assigns categories.
  #
  # @param rows [Array<Hash>] normalized product facts
  # @return [Array<Hash>] selected rows ordered by descending score
  def filter_and_rank(rows)
    filters = CONFIG.fetch(:filters)
    require_keywords = filters.fetch(:require_keywords).map(&:downcase)
    exclude_keywords = filters.fetch(:exclude_keywords).map(&:downcase)
    selected = rows.select do |row|
      title = row.fetch(:title).downcase
      rating = row[:rating]
      sold = row[:sold]
      price = row[:price]
      (require_keywords.empty? || require_keywords.any? { |word| title.include?(word) }) &&
        exclude_keywords.none? { |word| title.include?(word) } &&
        rating && rating >= filters.fetch(:min_rating) &&
        sold && sold >= filters.fetch(:min_sold) &&
        (!filters.fetch(:exclude_ads) || !row[:is_ad]) &&
        (!filters[:min_price] || (price && price >= filters[:min_price])) &&
        (!filters[:max_price] || (price && price <= filters[:max_price]))
    end

    selected.sort_by { |row| -score_for(row) }.first(CONFIG.fetch(:top_n)).map do |row|
      row.merge(category: category_for(row.fetch(:title)))
    end
  end

  # Calculates the configured weighted score for a normalized product row.
  #
  # @param row [Hash] normalized product facts
  # @return [Float] weighted score
  def score_for(row)
    weights = CONFIG.fetch(:score_weights)
    row.fetch(:sold, 0).to_f * weights.fetch(:sold).to_f +
      row.fetch(:rating, 0).to_f * weights.fetch(:rating).to_f +
      (row[:is_mall] ? weights.fetch(:is_mall).to_f : 0) +
      row.fetch(:discount, 0).to_f * weights.fetch(:discount).to_f
  end

  # Returns the first matching category after honoring category-specific exclusions.
  #
  # @param title [String] product title
  # @return [String, nil] category ID or nil if no category matches
  def category_for(title)
    normalized_title = title.downcase
    CONFIG.fetch(:categories).each do |category|
      next if category.fetch(:exclude_keywords).any? { |word| normalized_title.include?(word.downcase) }
      return category.fetch(:id) if category.fetch(:match_keywords).any? { |word| normalized_title.include?(word.downcase) }
    end

    nil
  end

  # Normalizes product facts, dropping duplicate and invalid source URLs.
  #
  # @param rows [Array<CSV::Row>] parsed rows with required headers
  # @return [Array<Array<Hash>, Integer>] normalized unique rows and invalid row count
  def normalize_rows(rows)
    seen_urls = {}
    failed = 0
    normalized = rows.filter_map do |source_row|
      row = normalize_row(source_row)
      unless row && shopee_vietnam_url?(row[:url])
        failed += 1
        next
      end
      next if seen_urls[row[:url]]

      seen_urls[row[:url]] = true
      row
    rescue ArgumentError, TypeError
      failed += 1
      nil
    end

    [ normalized, failed ]
  end

  # Converts one CSV row to typed product attributes while preserving its raw facts.
  #
  # @param source_row [CSV::Row] a row from the uploaded file
  # @return [Hash, nil] normalized row or nil when required facts are absent
  def normalize_row(source_row)
    raw = source_row.to_h
    title = raw["name"]&.strip
    url = raw["url"]&.strip
    return unless title.present? && url.present?

    {
      source_product_id: nil,
      merchant: "Shopee",
      title: title,
      description: nil,
      images: raw["image"].present? ? [ raw["image"].strip ].to_json : nil,
      price: parse_decimal(raw["price"]),
      original_price: nil,
      discount: parse_decimal(raw["discount"]),
      category: nil,
      rating: parse_decimal(raw["rating"]),
      sold: parse_sold(raw["sold"]),
      is_mall: parse_boolean(raw["is_mall"]),
      is_ad: parse_boolean(raw["is_ad"]),
      commission: nil,
      original_product_url: url,
      url: url,
      raw_source_data: raw.to_json
    }
  end

  # Parses a Dataminer price/rating/discount value without inventing a value for missing data.
  #
  # @param value [String, nil] CSV numeric field
  # @return [BigDecimal, nil] parsed decimal or nil for blank input
  def parse_decimal(value)
    cleaned = value.to_s.strip.delete_suffix("%")
    return if cleaned.empty?

    if cleaned.include?(",")
      cleaned = cleaned.delete(".").tr(",", ".")
    elsif cleaned.match?(/\A\d{1,3}(?:\.\d{3})+\z/)
      cleaned = cleaned.delete(".")
    end

    BigDecimal(cleaned)
  end

  # Parses sold counts such as "1.5k" and "10k+" into integers.
  #
  # @param value [String, nil] CSV sold field
  # @return [Integer, nil] normalized count or nil for blank input
  def parse_sold(value)
    cleaned = value.to_s.strip.downcase
    return if cleaned.empty?

    multiplier = cleaned.match?(/k\+?\z/) ? 1_000 : 1
    numeric = cleaned.delete_suffix("+").delete_suffix("k").tr(",", ".")
    (BigDecimal(numeric) * multiplier).to_i
  end

  # Parses a CSV boolean while leaving unknown values unset.
  #
  # @param value [String, nil] CSV boolean field
  # @return [Boolean, nil] parsed boolean or nil for unknown input
  def parse_boolean(value)
    case value.to_s.strip.downcase
    when "1", "true", "yes" then true
    when "0", "false", "no" then false
    end
  end

  # Checks the allowed Shopee Vietnam HTTPS URL boundary before forwarding a URL.
  #
  # @param value [String] product URL
  # @return [Boolean] whether the URL targets Shopee Vietnam over HTTPS
  def shopee_vietnam_url?(value)
    uri = URI.parse(value)
    uri.is_a?(URI::HTTPS) && %w[shopee.vn www.shopee.vn].include?(uri.host&.downcase) && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end

  # Saves a successful link while counting missing links and row-level persistence errors.
  #
  # @param row [Hash] normalized CSV facts
  # @param link [Hash, nil] ACCESSTRADE link mapping for the original URL
  # @return [void]
  def persist_product(row, link)
    return @failed_count += 1 unless link && link["aff_link"].present?

    product = current_user.products.find_or_initialize_by(
      affiliate_provider: "accesstrade",
      original_product_url: row.fetch(:original_product_url)
    )
    product.assign_attributes(row.except(:url, :is_ad).merge(affiliate_url: link.fetch("aff_link"), last_synced_at: Time.current))
    if product.save
      @imported_count += 1
    else
      @failed_count += 1
    end
  rescue KeyError, ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    @failed_count += 1
  end

  # Adds a file-level error and returns an empty row list.
  #
  # @param message [String] validation error for the uploaded file
  # @return [Array] no parsed rows
  def add_file_error(message)
    errors.add(:base, message)
    []
  end
end
