# frozen_string_literal: true

class SocialConnections::SyncDestinationOperation < MainOperation
  attr_reader :destination

  # @param params [Hash] :current_user and :page_id
  # @param client [MetaGraphClient] Meta API boundary
  # @return [void]
  def initialize(params:, client: MetaGraphClient.new)
    super(params:)
    @errors = ActiveModel::Errors.new(self)
    @page_id = params[:page_id].to_s
    @client = client
  end

  # Verifies recent Page ownership, fetches its token fresh, and syncs a destination.
  #
  # @return [void]
  def call
    step_load_connection
    return if error?

    step_validate_discovered_page
    return if error?

    step_fetch_page_token
    step_save_destination unless error?
  end

  private

  # Loads only the current user's connected Facebook account.
  #
  # @return [void]
  def step_load_connection
    @social_connection = current_user&.social_connection
    errors.add(:base, "Kết nối Facebook trước khi chọn Page") unless @social_connection&.access_token.present?
  end

  # Validates the Page id against this connection's recent discovery results.
  #
  # @return [void]
  def step_validate_discovered_page
    @page = Array(Rails.cache.read(cache_key)).find { |entry| entry["page_id"] == @page_id }
    errors.add(:base, "Page không nằm trong danh sách vừa tải. Hãy tải lại danh sách Page.") unless @page
  end

  # Fetches a fresh Page token from Meta using the account-level user token.
  #
  # @return [void]
  def step_fetch_page_token
    @page_access_token = @client.fetch_page_token(page_id: @page_id, access_token: @social_connection.access_token)
  rescue MetaGraphClient::ApiError
    errors.add(:base, "Không thể lấy quyền truy cập Page. Hãy tải lại danh sách Page.")
  rescue MetaGraphClient::TransportError
    errors.add(:base, "Không thể kết nối Meta lúc này. Vui lòng thử lại.")
  end

  # Creates or updates the Page destination with its encrypted Page token.
  #
  # @return [void]
  def step_save_destination
    @destination = @social_connection.social_destinations.find_or_initialize_by(page_id: @page_id)
    @destination.assign_attributes(destination_type: "page", name: @page.fetch("name"), page_access_token: @page_access_token)
    errors.merge!(@destination.errors) unless @destination.save
  end

  # Builds the per-connection discovery cache key.
  #
  # @return [String] cache key
  def cache_key
    "facebook_pages:#{@social_connection.id}"
  end
end
