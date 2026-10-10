class AutoResponder::SelectRuleService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:auto_responder)
  RULE_TYPES = CONFIGURATION.fetch(:rule_types)

  attr_reader :rule, :reply_text

  # Initializes the rule selection for a stored public comment.
  #
  # @param social_destination_id [Integer] the destination that received the comment
  # @param comment_text [String] the public comment text
  # @return [AutoResponder::SelectRuleService] the configured service
  def initialize(social_destination_id:, comment_text:)
    @social_destination_id = social_destination_id
    @comment_text = comment_text
    super()
  end

  # Selects the most specific active keyword response or the destination default.
  #
  # @return [Boolean] whether an active response rule was found
  def call
    step_select_rule
    success?
  end

  private

  def step_select_rule
    destination = SocialDestination.find_by(id: @social_destination_id)
    return step_fail!("Không tìm thấy đích nhận bình luận.") unless destination

    default_rule = destination.auto_reply_rules.find_by(
      rule_type: CONFIGURATION.fetch(:default_rule_type),
      enabled: true
    )
    return step_fail!("Đích này chưa có câu trả lời mặc định đang bật.") unless default_rule

    @rule = step_matching_keyword_rules(destination).first || default_rule
    @reply_text = rule.reply_text
    step_succeed!
  end

  def step_matching_keyword_rules(destination)
    normalized_comment = @comment_text.to_s.downcase
    destination.auto_reply_rules.where(rule_type: RULE_TYPES.fetch(:keyword), enabled: true)
      .order(:created_at, :id)
      .select { |candidate| normalized_comment.include?(candidate.keyword.downcase) }
      .sort_by { |candidate| [ -candidate.keyword.length, candidate.created_at, candidate.id ] }
  end
end
