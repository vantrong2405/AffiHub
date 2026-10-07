class SocialDestinations::CreateService < ApplicationService
  attr_reader :social_destination

  # Initializes selection of one Page available to a connected Facebook profile.
  #
  # @param social_connection_id [Integer] the connected profile
  # @param external_id [String] the Page ID explicitly selected by the user
  # @return [SocialDestinations::CreateService] the configured service
  def initialize(social_connection_id:, external_id:)
    @social_connection_id = social_connection_id
    @external_id = external_id.to_s
    super()
  end

  # Persists only the Page selected by its connected profile.
  #
  # @return [Boolean] whether the selected destination was saved
  def call
    return false unless step_load_connection
    return false unless step_load_pages
    return false unless step_select_page

    step_persist_destination
    success?
  end

  private

  def step_load_connection
    @social_connection = SocialConnection.find_by(id: @social_connection_id)
    return step_fail!("Không tìm thấy kết nối Facebook đang hoạt động.") unless @social_connection&.connected?
    return step_fail!("Kết nối này không phải Facebook.") unless @social_connection.provider == "facebook"

    true
  end

  def step_load_pages
    @pages = Meta::Client.new.pages(access_token: @social_connection.access_token)
    true
  rescue Meta::Client::Error
    step_fail!("Không thể đọc danh sách Page từ Meta.")
  end

  def step_select_page
    @page = @pages.find { |page| page["id"] == @external_id }
    return step_fail!("Page đã chọn không thuộc profile Facebook đang kết nối.") unless @page
    return step_fail!("Page chưa cấp quyền tạo nội dung.") unless @page.fetch("tasks", []).include?("CREATE_CONTENT")
    return step_fail!("Meta không trả Page Access Token cho Page đã chọn.") if @page["access_token"].blank?

    true
  end

  def step_persist_destination
    @social_destination = @social_connection.social_destinations.find_or_initialize_by(external_id: @external_id)
    @social_destination.assign_attributes(
      provider: "facebook",
      name: @page.fetch("name"),
      access_token: @page.fetch("access_token"),
      status: :connected,
      metadata: { "tasks" => @page.fetch("tasks", []) }
    )
    @social_destination.save!
    step_succeed!
  end
end
