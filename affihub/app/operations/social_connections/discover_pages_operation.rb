# frozen_string_literal: true

class SocialConnections::DiscoverPagesOperation < MainOperation
  CACHE_TTL = 10.minutes

  attr_reader :social_connection, :pages, :destinations

  # @param params [Hash] :current_user
  # @param client [MetaGraphClient] Meta API boundary
  # @return [void]
  def initialize(params:, client: MetaGraphClient.new)
    super(params:)
    @errors = ActiveModel::Errors.new(self)
    @client = client
  end

  # Discovers Pages through the connected user token and caches metadata only.
  #
  # @return [void]
  def call
    step_load_connection
    return if error?

    step_discover_pages
  end

  private

  # Loads only the current user's Facebook connection.
  #
  # @return [void]
  def step_load_connection
    @social_connection = current_user&.social_connection
    errors.add(:base, "Kết nối Facebook trước khi tải danh sách Page") unless @social_connection&.access_token.present?
    @destinations = @social_connection&.social_destinations&.index_by(&:page_id) || {}
  end

  # Fetches Page metadata and writes a token-free ownership cache.
  #
  # @return [void]
  def step_discover_pages
    @pages = @client.list_pages(access_token: @social_connection.access_token).map do |page|
      page.slice("id", "name", "picture")
    end
    metadata = @pages.map { |page| { "page_id" => page.fetch("id"), "name" => page.fetch("name") } }
    Rails.cache.write(cache_key, metadata, expires_in: CACHE_TTL)
  rescue MetaGraphClient::ApiError, KeyError
    @pages = []
    errors.add(:base, "Facebook không thể trả danh sách Page lúc này")
  rescue MetaGraphClient::TransportError
    @pages = []
    errors.add(:base, "Không thể kết nối Meta lúc này. Vui lòng thử lại.")
  end

  # Builds the per-connection Page discovery cache key.
  #
  # @return [String] cache key
  def cache_key
    "facebook_pages:#{@social_connection.id}"
  end
end
