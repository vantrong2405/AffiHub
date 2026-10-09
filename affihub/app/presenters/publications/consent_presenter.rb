class Publications::ConsentPresenter
  YOUTUBE_PRIVACY_LABELS = {
    "private" => "Riêng tư",
    "unlisted" => "Không công khai",
    "public" => "Công khai"
  }.freeze
  TIKTOK_PRIVACY_LABELS = {
    "SELF_ONLY" => "Chỉ mình tôi",
    "MUTUAL_FOLLOW_FRIENDS" => "Bạn bè",
    "PUBLIC_TO_EVERYONE" => "Mọi người"
  }.freeze
  DISCLOSURE_OPTIONS = [ [ "Có", "1" ], [ "Không", "0" ] ].freeze
  TIKTOK_INTERACTIONS = [
    [ "allow_comment", "comment", "Cho phép bình luận" ],
    [ "allow_duet", "duet", "Cho phép Duet" ],
    [ "allow_stitch", "stitch", "Cho phép Stitch" ]
  ].freeze

  attr_reader :publication

  # Prepares the consent and disclosure state displayed for one Publication.
  #
  # @param publication [Publication] the reviewed Publication
  # @param youtube_privacy_statuses [Array<String>, nil] privacy choices from YouTube config
  # @param tiktok_privacy_levels [Array<String>, nil] choices returned by TikTok creator info
  # @param tiktok_disabled_interactions [Hash, nil] interactions disabled by the creator
  # @param tiktok_creator_info_available [Boolean] whether creator settings were verified
  # @param tiktok_cap_status [String, nil] configured TikTok cap status
  # @param tiktok_cap_status_values [Hash, nil] provider cap status values
  # @param tiktok_brand_content_enabled [Boolean, nil] whether branded content is available
  # @return [Publications::ConsentPresenter] the prepared presentation state
  def initialize(publication:, youtube_privacy_statuses:, tiktok_privacy_levels:, tiktok_disabled_interactions:,
                 tiktok_creator_info_available:, tiktok_cap_status:, tiktok_cap_status_values:,
                 tiktok_brand_content_enabled:)
    @publication = publication
    @youtube_privacy_statuses = Array(youtube_privacy_statuses)
    @tiktok_privacy_levels = Array(tiktok_privacy_levels)
    @tiktok_disabled_interactions = tiktok_disabled_interactions.to_h
    @tiktok_creator_info_available = tiktok_creator_info_available
    @tiktok_cap_status = tiktok_cap_status
    @tiktok_cap_status_values = tiktok_cap_status_values.to_h
    @tiktok_brand_content_enabled = tiktok_brand_content_enabled
    @consent_snapshot = publication.consent_snapshot.to_h.stringify_keys
  end

  # Returns provider-specific section copy for the publication form.
  #
  # @return [String] the section heading
  def section_title
    return "Nội dung và xác nhận YouTube" if youtube?
    return "Nội dung và xác nhận TikTok" if tiktok?

    "Caption riêng cho Page này"
  end

  # Returns provider-specific instructions for the publication form.
  #
  # @return [String] the section description
  def section_description
    return "Chọn quyền riêng tư và khai báo nội dung cho đúng video này." if youtube?
    return "Chọn quyền riêng tư và khai báo nội dung cho creator cùng render này." if tiktok?

    "Caption chỉ được sửa khi bài còn là bản nháp."
  end

  # Returns the matching consent form partial, when the provider requires one.
  #
  # @return [String, nil] the partial name
  def consent_partial
    return "youtube_consent_fields" if youtube?
    return "tiktok_consent_fields" if tiktok?
  end

  # Returns the submit label for the selected provider.
  #
  # @return [String] the submit button label
  def submit_label
    return "Lưu caption và xác nhận nội dung" if youtube?
    return "Lưu caption và xác nhận TikTok" if tiktok?

    "Lưu caption"
  end

  # Returns YouTube privacy choices with their Vietnamese labels.
  #
  # @return [Array<Array<String>>] prompt and configured options
  def youtube_privacy_options
    [ [ "Chọn quyền riêng tư", "" ] ] + @youtube_privacy_statuses.map do |status|
      [ YOUTUBE_PRIVACY_LABELS.fetch(status, status), status ]
    end
  end

  # Returns the required YouTube disclosure choices.
  #
  # @return [Array<Array<String>>] prompt and disclosure options
  def youtube_disclosure_options
    disclosure_options
  end

  # Returns the required yes/no disclosure choices used by provider forms.
  #
  # @return [Array<Array<String>>] prompt and disclosure options
  def disclosure_options
    [ [ "Chọn câu trả lời", "" ] ] + DISCLOSURE_OPTIONS
  end

  # Returns the saved YouTube privacy choice.
  #
  # @return [String, nil] selected privacy status
  def youtube_privacy_choice
    @consent_snapshot["privacy_status"]
  end

  # Returns the saved YouTube made-for-kids disclosure choice.
  #
  # @return [String, nil] selected disclosure value
  def youtube_made_for_kids_choice
    boolean_choice(@consent_snapshot["self_declared_made_for_kids"])
  end

  # Returns the saved YouTube synthetic-media disclosure choice.
  #
  # @return [String, nil] selected disclosure value
  def youtube_synthetic_media_choice
    boolean_choice(@consent_snapshot["contains_synthetic_media"])
  end

  # Reports whether YouTube upload terms were confirmed for this Publication.
  #
  # @return [Boolean] whether the saved terms confirmation is true
  def youtube_upload_terms_confirmed?
    @consent_snapshot["upload_terms_confirmed"] == true
  end

  # Returns TikTok privacy options with their Vietnamese labels.
  #
  # @return [Array<Array<String>>] prompt and creator-approved options
  def tiktok_privacy_options
    [ [ "Chọn quyền riêng tư", "" ] ] + @tiktok_privacy_levels.map do |level|
      [ TIKTOK_PRIVACY_LABELS.fetch(level, level), level ]
    end
  end

  # Returns the saved TikTok privacy choice when its consent still matches this Publication.
  #
  # @return [String, nil] selected privacy level
  def tiktok_privacy_choice
    consent_matches_publication? ? @consent_snapshot["privacy_level"] : nil
  end

  # Returns the creator-approved TikTok interaction controls.
  #
  # @return [Array<Hash>] interaction field state for the consent form
  def tiktok_interactions
    TIKTOK_INTERACTIONS.map do |field, key, label|
      disabled = @tiktok_disabled_interactions.fetch(key, true)
      {
        field:,
        key:,
        label:,
        disabled:,
        show_disabled_note: @tiktok_creator_info_available && disabled,
        checked: consent_matches_publication? && @consent_snapshot[field] == true && !disabled
      }
    end
  end

  # Returns TikTok cap messaging and its visual severity.
  #
  # @return [Hash, nil] safe message state
  def tiktok_cap_message
    return cap_message(:warning, "TikTok báo creator này đã chạm giới hạn đăng hiện tại.") if @tiktok_cap_status == @tiktok_cap_status_values[:creator]
    return cap_message(:warning, "Ứng dụng TikTok đã chạm giới hạn creator hiện tại.") if @tiktok_cap_status == @tiktok_cap_status_values[:app]
    return cap_message(:info, "Chưa thể kiểm tra số bài còn lại. TikTok không cung cấp bộ đếm quota trong thông tin creator.") if @tiktok_creator_info_available

    cap_message(:warning, "Chưa thể kiểm tra số bài còn lại. Không lấy được trạng thái giới hạn từ TikTok.")
  end

  # Reports whether TikTok supplied a privacy choice.
  #
  # @return [Boolean] whether a privacy choice can be selected
  def tiktok_privacy_available?
    @tiktok_privacy_levels.present?
  end

  # Returns the warning displayed when TikTok supplied no privacy choices.
  #
  # @return [String, nil] safe guidance for unavailable privacy choices
  def tiktok_privacy_warning
    return if tiktok_privacy_available?

    "Chưa lấy được lựa chọn quyền riêng tư từ TikTok. Kiểm tra lại kết nối trước khi xác nhận đăng."
  end

  # Reports whether TikTok creator interaction settings were verified.
  #
  # @return [Boolean] whether creator settings are available
  def tiktok_creator_info_available?
    @tiktok_creator_info_available
  end

  # Returns the warning displayed when creator interaction settings are unavailable.
  #
  # @return [String, nil] safe guidance for unavailable creator settings
  def tiktok_creator_settings_warning
    return if tiktok_creator_info_available?

    "Không thể kiểm tra cài đặt tương tác. Kết nối lại TikTok trước khi xác nhận đăng."
  end

  # Reports whether the creator disabled a selected interaction.
  #
  # @param interaction [String] the interaction identifier
  # @return [Boolean] whether the interaction is disabled
  def tiktok_interaction_disabled?(interaction)
    @tiktok_disabled_interactions.fetch(interaction, true)
  end

  # Reports whether TikTok allows branded content in the configured privacy state.
  #
  # @return [Boolean] whether branded content is available
  def tiktok_brand_content_enabled?
    @tiktok_brand_content_enabled
  end

  # Reports whether the TikTok brand-content checkbox must be disabled.
  #
  # @return [Boolean] whether the current app configuration disables branded content
  def tiktok_brand_content_disabled?
    !tiktok_brand_content_enabled?
  end

  # Returns the saved TikTok AI disclosure choice when consent still matches this Publication.
  #
  # @return [String, nil] selected disclosure value
  def tiktok_ai_disclosure_choice
    consent_matches_publication? ? boolean_choice(@consent_snapshot["is_aigc"]) : nil
  end

  # Reports whether the creator confirmed the private-account state.
  #
  # @return [Boolean] whether the saved confirmation is true
  def tiktok_private_account_confirmed?
    consent_matches_publication? && @consent_snapshot["creator_account_private"] == true
  end

  # Reports whether the creator confirmed music usage rights.
  #
  # @return [Boolean] whether the saved confirmation is true
  def tiktok_music_usage_confirmed?
    consent_matches_publication? && @consent_snapshot["music_usage_confirmed"] == true
  end

  # Reports whether the saved organic brand disclosure is selected.
  #
  # @return [Boolean] whether the saved disclosure is true
  def tiktok_brand_organic_selected?
    consent_matches_publication? && @consent_snapshot["brand_organic_toggle"] == true
  end

  # Reports whether the saved branded-content disclosure is selected and available.
  #
  # @return [Boolean] whether the saved disclosure is true and enabled
  def tiktok_brand_content_selected?
    consent_matches_publication? && @consent_snapshot["brand_content_toggle"] == true && tiktok_brand_content_enabled?
  end

  # Returns the TikTok brand-content disclosure guidance.
  #
  # @return [String, nil] explanatory guidance when the option is unavailable
  def tiktok_brand_content_guidance
    return if tiktok_brand_content_enabled?

    "Ứng dụng hiện chỉ cho phép đăng riêng tư; nội dung quảng bá thương hiệu khác cần quyền đăng công khai đã được TikTok duyệt."
  end

  private

  def youtube?
    publication.social_destination.provider == "youtube"
  end

  def tiktok?
    publication.social_destination.provider == "tiktok"
  end

  def consent_matches_publication?
    social_destination = publication.social_destination
    @consent_snapshot["tiktok_social_connection_id"].to_s == social_destination.social_connection_id.to_s &&
      @consent_snapshot["tiktok_creator_id"].to_s == social_destination.external_id.to_s &&
      @consent_snapshot["tiktok_render_version_id"].to_s == publication.render_version_id.to_s &&
      @consent_snapshot["tiktok_publication_id"].to_s == publication.id.to_s
  end

  def boolean_choice(value)
    value == true ? "1" : ("0" if value == false)
  end

  def cap_message(severity, text)
    {
      severity:,
      role: severity == :info ? "status" : "alert",
      alert_class: severity == :info ? "alert-info" : "alert-warning",
      text:
    }
  end
end
