module SocialProvidersHelper
  SOCIAL_PROVIDER_NAMES = {
    "facebook" => "Facebook",
    "instagram" => "Instagram",
    "tiktok" => "TikTok",
    "youtube" => "YouTube"
  }.freeze
  SOCIAL_OAUTH_PROVIDER_NAMES = {
    "facebook" => "Facebook",
    "instagram" => "Facebook",
    "tiktok" => "TikTok",
    "youtube" => "Google"
  }.freeze
  SOCIAL_DESTINATION_LABELS = {
    "facebook" => "Page",
    "instagram" => "tài khoản Instagram Business",
    "tiktok" => "tài khoản TikTok",
    "youtube" => "kênh"
  }.freeze

  # Returns the product label for a configured social provider.
  #
  # @param provider [String, Symbol] the configured social provider key
  # @return [String] the provider's user-facing product name
  def social_provider_name(provider)
    SOCIAL_PROVIDER_NAMES.fetch(provider.to_s, provider.to_s.humanize)
  end

  # Returns the destination noun displayed for a connected social provider.
  #
  # @param provider [String, Symbol] the connected social provider key
  # @return [String] the destination label
  def social_destination_name(provider)
    SOCIAL_DESTINATION_LABELS.fetch(provider.to_s, "đích đăng")
  end

  # Reports whether the provider supports selecting a destination after connection.
  #
  # @param provider [String, Symbol] the connected social provider key
  # @return [Boolean] whether a destination can be selected
  def social_destination_selection_supported?(provider)
    social_provider_configuration(provider).fetch(:destination_selection_supported, false)
  end

  # Returns the configured provider type used to select a destination workflow.
  #
  # @param provider [String, Symbol] the connected social provider key
  # @return [String, nil] the configured destination kind
  def social_destination_kind(provider)
    social_provider_configuration(provider)[:destination_kind]
  end

  # Returns the provider's OAuth product name for connection instructions.
  #
  # @param provider [String, Symbol] the social provider key
  # @return [String] the configured OAuth product name
  def social_oauth_provider_name(provider)
    SOCIAL_OAUTH_PROVIDER_NAMES.fetch(provider.to_s, social_provider_name(provider))
  end

  # Returns Vietnamese setup instructions for the configured OAuth flow.
  #
  # @param provider [String, Symbol] the social provider key
  # @return [String] the connection instruction
  def social_connection_instruction(provider)
    configuration = social_provider_configuration(provider)
    return "Bạn sẽ dùng Facebook Login for Business để cấp quyền cho Instagram, sau đó chọn Page liên kết Instagram Business." if
      configuration[:oauth_flow] == "instagram_business_login"

    "Bạn sẽ xác nhận quyền truy cập tại #{social_oauth_provider_name(provider)}, sau đó chọn đích đăng video."
  end

  # Returns the OAuth authorization notice for the configured provider flow.
  #
  # @param provider [String, Symbol] the social provider key
  # @return [String] the authorization notice
  def social_authorization_notice(provider)
    configuration = social_provider_configuration(provider)
    return "Bạn sẽ được chuyển sang Facebook Login for Business để xác nhận quyền truy cập." if
      configuration[:oauth_flow] == "instagram_business_login"

    "Bạn sẽ được chuyển sang #{social_oauth_provider_name(provider)} để xác nhận quyền truy cập."
  end

  private

  def social_provider_configuration(provider)
    SocialConnections::ProviderConfiguration.for(provider)
  rescue KeyError
    {}
  end
end
