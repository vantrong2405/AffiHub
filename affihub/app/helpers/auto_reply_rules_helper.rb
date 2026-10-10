module AutoReplyRulesHelper
  AUTO_REPLY_CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys
    .fetch(:auto_responder)
  RULE_TYPE_CONFIGURATION = AUTO_REPLY_CONFIGURATION.fetch(:rule_types)
  RULE_TYPE_LABELS = {
    RULE_TYPE_CONFIGURATION.fetch(:default) => "Câu trả lời mặc định",
    RULE_TYPE_CONFIGURATION.fetch(:keyword) => "Theo từ khóa"
  }.freeze

  # Returns rule-type choices with UI copy kept in Ruby.
  #
  # @return [Array<Array<String>>] labels and configured rule-type values
  def auto_reply_rule_type_options
    RULE_TYPE_LABELS.map { |rule_type, label| [ label, rule_type ] }
  end

  # Returns the Vietnamese label for a configured rule type.
  #
  # @param rule_type [String, Symbol] the stored rule type
  # @return [String] the user-facing rule type label
  def auto_reply_rule_type_label(rule_type)
    RULE_TYPE_LABELS.fetch(rule_type.to_s, "Loại quy tắc khác")
  end

  # Returns the provider and name shown for a comment destination.
  #
  # @param social_destination [SocialDestination] the destination receiving comments
  # @return [String] the destination label
  def auto_reply_destination_label(social_destination)
    "#{social_provider_name(social_destination.provider)} · #{social_destination.name}"
  end

  # Returns destination choices ready for a Rails select.
  #
  # @param social_destinations [Array<SocialDestination>] connected comment destinations
  # @return [Array<Array<Object>>] destination labels paired with record ids
  def auto_reply_destination_options(social_destinations)
    social_destinations.map do |social_destination|
      [ auto_reply_destination_label(social_destination), social_destination.id ]
    end
  end

  # Reports whether a destination list can populate the new rule form.
  #
  # @param social_destinations [Array<SocialDestination>] connected comment destinations
  # @return [Boolean] whether the form has a destination choice
  def auto_reply_destinations_present?(social_destinations)
    social_destinations.present?
  end

  # Reports whether the rule index has rows to display.
  #
  # @param auto_reply_rules [Array<AutoReplyRule>] rules loaded for the index
  # @return [Boolean] whether at least one rule is available
  def auto_reply_rules_present?(auto_reply_rules)
    auto_reply_rules.present?
  end

  # Returns the optional keyword caption for a rule list row.
  #
  # @param auto_reply_rule [AutoReplyRule] the saved rule
  # @return [String, nil] the keyword caption when the rule matches a keyword
  def auto_reply_rule_keyword_caption(auto_reply_rule)
    return if auto_reply_rule.keyword.blank?

    "Từ khóa: #{auto_reply_rule.keyword}"
  end

  # Reports whether a rule has a keyword to show in the rule list.
  #
  # @param auto_reply_rule [AutoReplyRule] the saved rule
  # @return [Boolean] whether the rule has a keyword
  def auto_reply_rule_keyword_present?(auto_reply_rule)
    auto_reply_rule.keyword.present?
  end

  # Returns the keyword or its non-applicable label for a rule detail.
  #
  # @param auto_reply_rule [AutoReplyRule] the saved rule
  # @return [String] the keyword display value
  def auto_reply_rule_keyword_value(auto_reply_rule)
    auto_reply_rule.keyword.presence || "Không dùng từ khóa"
  end

  # Returns the enabled or disabled rule label.
  #
  # @param auto_reply_rule [AutoReplyRule] the saved rule
  # @return [String] the user-facing enabled state
  def auto_reply_rule_status_label(auto_reply_rule)
    auto_reply_rule.enabled? ? "Đang bật" : "Đã tắt"
  end

  # Returns the daisyUI badge tone for a rule's enabled state.
  #
  # @param auto_reply_rule [AutoReplyRule] the saved rule
  # @return [String] a daisyUI badge tone class
  def auto_reply_rule_status_badge_class(auto_reply_rule)
    auto_reply_rule.enabled? ? "badge-success" : "badge-ghost"
  end
end
