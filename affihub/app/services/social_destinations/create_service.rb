class SocialDestinations::CreateService < ApplicationService
  attr_reader :social_connection, :social_destinations

  # Initializes selection of Pages available to a connected Meta profile.
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
    return step_create_channels if @provider_configuration[:destination_kind] == "channel"
    return false unless step_load_pages
    return false unless step_select_pages
    return false unless step_validate_pages

    step_persist_destinations
    success?
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

  def step_validate_selection
    return step_fail!("Chọn ít nhất một Page.") if @external_ids.empty?

    true
  end

  def step_load_pages
    @pages = Meta::Client.new(provider: @social_connection.provider).pages(access_token: @social_connection.access_token)
    true
  rescue Meta::Client::Error
    step_fail!("Không thể đọc danh sách Page từ Meta.")
  end

  def step_create_channels
    return false unless step_load_channels
    return false unless step_select_channels

    step_persist_channels
    success?
  end

  def step_load_channels
    @channels = Youtube::Client.new.channels(access_token: @social_connection.access_token)
    true
  rescue Youtube::Client::Error
    step_fail!("Không thể đọc danh sách kênh từ YouTube.")
  end

  def step_select_channels
    @selected_channels = @channels.select { |channel| @external_ids.include?(channel.fetch("id")) }
    return step_fail!("Một hoặc nhiều kênh không thuộc tài khoản đang kết nối.") unless @selected_channels.size == @external_ids.size

    true
  end

  def step_persist_channels
    @social_destinations = []
    SocialDestination.transaction do
      @selected_channels.each do |channel|
        destination = @social_connection.social_destinations.find_or_initialize_by(external_id: channel.fetch("id"))
        destination.assign_attributes(
          provider: @social_connection.provider,
          name: channel.fetch("name"),
          access_token: @social_connection.access_token,
          token_expires_at: @social_connection.token_expires_at,
          status: :connected,
          metadata: { "channel_id" => channel.fetch("id") }
        )
        destination.save!
        @social_destinations << destination
      end
    end
    step_succeed!
  rescue ActiveRecord::RecordInvalid
    @social_destinations = []
    step_fail!("Không thể lưu các kênh đã chọn.")
  end

  def step_select_pages
    @selected_pages = @pages.select { |page| @external_ids.include?(page["id"].to_s) }
    return step_fail!("Một hoặc nhiều Page không thuộc profile đang kết nối.") unless @selected_pages.size == @external_ids.size

    true
  end

  def step_validate_pages
    return step_fail!("Page chưa cấp quyền tạo nội dung.") if @selected_pages.any? { |page| !SocialDestination.can_create_content?(page.fetch("tasks", []), provider: @social_connection.provider) }
    return step_fail!("Meta không trả Page Access Token cho Page đã chọn.") if @selected_pages.any? { |page| page["access_token"].blank? }
    account_field = @provider_configuration[:destination_account_field]
    if account_field && @selected_pages.any? { |page| page.dig(account_field, "id").blank? }
      return step_fail!("Page chưa liên kết Instagram Business account.")
    end
    if account_field && @social_connection.provider == "instagram" && @selected_pages.any? { |page| !instagram_business_account?(page) }
      return step_fail!("MVP chỉ hỗ trợ tài khoản Instagram Business có Page liên kết.")
    end

    true
  end

  def instagram_business_account?(page)
    supported_types = @provider_configuration.fetch(:supported_destination_account_types)
    supported_types.include?(instagram_business_account_type(page))
  end

  def instagram_business_account_type(page)
    account_field = @provider_configuration.fetch(:destination_account_field)
    account = page[account_field] || page[account_field.to_sym] || {}
    account["account_type"] || account[:account_type]
  end

  def step_persist_destinations
    @social_destinations = []
    SocialDestination.transaction do
      @selected_pages.each do |page|
        account_field = @provider_configuration[:destination_account_field]
        external_id = account_field ? page.dig(account_field, "id").to_s : page.fetch("id").to_s
        metadata = { "tasks" => page.fetch("tasks", []) }
        if account_field
          metadata["page_id"] = page.fetch("id").to_s
          metadata["#{account_field}_id"] = external_id
          metadata["instagram_account_type"] = instagram_business_account_type(page) if @social_connection.provider == "instagram"
        end
        social_destination = @social_connection.social_destinations.find_or_initialize_by(external_id:)
        social_destination.assign_attributes(
          provider: @social_connection.provider,
          name: page.fetch("name"),
          access_token: page.fetch("access_token"),
          status: :connected,
          metadata:
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
