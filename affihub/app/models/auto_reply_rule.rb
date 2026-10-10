class AutoReplyRule < ApplicationRecord
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:auto_responder)
  RULE_TYPES = CONFIGURATION.fetch(:rule_types)

  attribute :enabled, :boolean, default: CONFIGURATION.fetch(:enabled_by_default)
  enum :rule_type, RULE_TYPES, default: CONFIGURATION.fetch(:default_rule_type).to_sym

  belongs_to :social_destination, inverse_of: :auto_reply_rules

  before_validation :normalize_keyword

  validates :reply_text, presence: true
  validates :keyword, presence: true, if: :keyword_rule?
  validates :keyword, uniqueness: { scope: :social_destination_id, case_sensitive: false }, if: :keyword_rule?
  validate :validate_rule_shape

  private

  def normalize_keyword
    self.keyword = keyword.to_s.strip.downcase if keyword_rule?
  end

  def validate_rule_shape
    if default_rule?
      errors.add(:keyword, "không được dùng cho quy tắc mặc định.") if keyword.present?
      step_validate_default_rule_uniqueness
    end
  end

  def step_validate_default_rule_uniqueness
    return if social_destination.blank?

    destination_rules = social_destination.auto_reply_rules.where(rule_type: CONFIGURATION.fetch(:default_rule_type))
    destination_rules = destination_rules.where.not(id:) if persisted?
    errors.add(:rule_type, "đích này đã có câu trả lời mặc định.") if destination_rules.exists?
  end

  def keyword_rule?
    rule_type == RULE_TYPES.fetch(:keyword)
  end

  def default_rule?
    rule_type == CONFIGURATION.fetch(:default_rule_type)
  end
end
