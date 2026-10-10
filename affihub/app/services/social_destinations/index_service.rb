class SocialDestinations::IndexService < ApplicationService
  attr_reader :social_connection, :available_pages, :available_destinations

  # Initializes the Meta Page selection service.
  #
  # @param social_connection_id [Integer] the connected profile
  # @return [SocialDestinations::IndexService] the configured service
  def initialize(social_connection_id:)
    @social_connection_id = social_connection_id
    super()
  end

  # Loads Page names, IDs, and content permissions without exposing Page tokens.
  #
  # @return [Boolean] whether available Pages were loaded
  def call
    return false unless step_load_connection
    return false unless step_load_available_destinations

    step_succeed!
  end

  private

  def step_load_connection
    @social_connection = SocialConnection.find_by(id: @social_connection_id)
    return step_fail!("Không tìm thấy kết nối Meta đang hoạt động.") unless @social_connection&.connected?

    @provider_configuration = SocialConnections::ProviderConfiguration.for(@social_connection.provider)
    unless @provider_configuration.key?(:page_fields) || @provider_configuration[:destination_kind] == "channel"
      return step_fail!("Kết nối này chưa hỗ trợ chọn đích đăng.")
    end

    true
  end

  def step_load_available_destinations
    return step_load_channels if @provider_configuration[:destination_kind] == "channel"

    pages = Meta::Client.new(provider: @social_connection.provider).pages(access_token: @social_connection.access_token)
    @available_pages = pages.filter_map { |page| step_page_choice(page) }
    @available_destinations = @available_pages
    true
  rescue Meta::Client::Error
    @available_pages = []
    @available_destinations = []
    step_fail!("Không thể đọc danh sách Page từ Meta.")
  end

  def step_load_channels
    @available_destinations = Youtube::Client.new.channels(access_token: @social_connection.access_token)
    @available_pages = @available_destinations
    true
  rescue Youtube::Client::Error
    @available_destinations = []
    @available_pages = []
    step_fail!("Không thể đọc danh sách kênh từ YouTube.")
  end

  def step_page_choice(page)
    return if page["id"].blank? || page["name"].blank?

    tasks = page.fetch("tasks", [])
    choice = {
      "id" => page.fetch("id").to_s,
      "name" => page.fetch("name"),
      "tasks" => tasks,
      "can_create_content" => SocialDestination.can_create_content?(tasks, provider: @social_connection.provider)
    }
    account_field = @provider_configuration[:destination_account_field]
    if account_field
      destination_account = page[account_field] || page[account_field.to_sym] || {}
      choice["#{account_field}_id"] = destination_account["id"] || destination_account[:id]
      if @social_connection.provider == "instagram"
        account_type = destination_account["account_type"] || destination_account[:account_type]
        choice["instagram_account_type"] = account_type
        choice["instagram_account_eligible"] = @provider_configuration
          .fetch(:supported_destination_account_types)
          .include?(account_type)
      end
    end
    choice
  end
end
