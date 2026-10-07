class SocialDestinations::CreateService < ApplicationService
  attr_reader :social_connection, :social_destinations

  # Initializes selection of Pages available to a connected Facebook profile.
  #
  # @param social_connection_id [Integer] the connected profile
  # @param external_ids [Array<String>] Page IDs explicitly selected by the user
  # @return [SocialDestinations::CreateService] the configured service
  def initialize(social_connection_id:, external_ids:)
    @social_connection_id = social_connection_id
    @external_ids = Array(external_ids).map(&:to_s).reject(&:blank?).uniq
    super()
  end

  # Persists only authorized Pages selected by the connected profile.
  #
  # @return [Boolean] whether every selected destination was saved
  def call
    return false unless step_load_connection
    return false unless step_validate_selection
    return false unless step_load_pages
    return false unless step_select_pages
    return false unless step_validate_pages

    step_persist_destinations
    success?
  end

  private

  def step_load_connection
    @social_connection = SocialConnection.find_by(id: @social_connection_id)
    return step_fail!("Không tìm thấy kết nối Facebook đang hoạt động.") unless @social_connection&.connected?
    return step_fail!("Kết nối này không phải Facebook.") unless @social_connection.provider == "facebook"

    true
  end

  def step_validate_selection
    return step_fail!("Chọn ít nhất một Page.") if @external_ids.empty?

    true
  end

  def step_load_pages
    @pages = Meta::Client.new.pages(access_token: @social_connection.access_token)
    true
  rescue Meta::Client::Error
    step_fail!("Không thể đọc danh sách Page từ Meta.")
  end

  def step_select_pages
    @selected_pages = @pages.select { |page| @external_ids.include?(page["id"].to_s) }
    return step_fail!("Một hoặc nhiều Page không thuộc profile Facebook đang kết nối.") unless @selected_pages.size == @external_ids.size

    true
  end

  def step_validate_pages
    return step_fail!("Page chưa cấp quyền tạo nội dung.") if @selected_pages.any? { |page| !SocialDestination.can_create_content?(page.fetch("tasks", [])) }
    return step_fail!("Meta không trả Page Access Token cho Page đã chọn.") if @selected_pages.any? { |page| page["access_token"].blank? }

    true
  end

  def step_persist_destinations
    @social_destinations = []
    SocialDestination.transaction do
      @selected_pages.each do |page|
        social_destination = @social_connection.social_destinations.find_or_initialize_by(external_id: page.fetch("id").to_s)
        social_destination.assign_attributes(
          provider: "facebook",
          name: page.fetch("name"),
          access_token: page.fetch("access_token"),
          status: :connected,
          metadata: { "tasks" => page.fetch("tasks", []) }
        )
        social_destination.save!
        @social_destinations << social_destination
      end
    end
    step_succeed!
  rescue ActiveRecord::RecordInvalid
    @social_destinations = []
    step_fail!("Không thể lưu các Page đã chọn.")
  end
end
