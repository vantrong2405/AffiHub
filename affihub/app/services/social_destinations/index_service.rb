class SocialDestinations::IndexService < ApplicationService
  attr_reader :social_connection, :available_pages

  # Initializes the Facebook Page selection service.
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
    return false unless step_load_available_pages

    step_succeed!
  end

  private

  def step_load_connection
    @social_connection = SocialConnection.find_by(id: @social_connection_id)
    return step_fail!("Không tìm thấy kết nối Facebook đang hoạt động.") unless @social_connection&.connected?
    return step_fail!("Kết nối này không phải Facebook.") unless @social_connection.provider == "facebook"

    true
  end

  def step_load_available_pages
    pages = Meta::Client.new.pages(access_token: @social_connection.access_token)
    @available_pages = pages.filter_map { |page| step_page_choice(page) }
    true
  rescue Meta::Client::Error
    @available_pages = []
    step_fail!("Không thể đọc danh sách Page từ Meta.")
  end

  def step_page_choice(page)
    return if page["id"].blank? || page["name"].blank?

    tasks = page.fetch("tasks", [])
    {
      "id" => page.fetch("id").to_s,
      "name" => page.fetch("name"),
      "tasks" => tasks,
      "can_create_content" => SocialDestination.can_create_content?(tasks)
    }
  end
end
