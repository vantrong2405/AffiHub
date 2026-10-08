class AiProviderConnection < ApplicationRecord
  CONFIGURATION = Rails.application.config_for(:ai_providers).deep_symbolize_keys
  STATUS_CONFIGURATION = CONFIGURATION.fetch(:statuses).fetch(:ai_provider_connection)
  PROVIDERS = CONFIGURATION.fetch(:providers).filter_map do |provider, provider_configuration|
    provider.to_s if provider_configuration.fetch(:enabled)
  end.freeze

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  encrypts :access_token, :refresh_token, :id_token

  validates :provider, :provider_subject, :provider_client_id, :access_token, presence: true
  validates :provider, inclusion: { in: PROVIDERS }
  validates :provider_subject, uniqueness: {
    scope: [ :provider, :provider_client_id ],
    message: "đã được sử dụng"
  }
  validate :selected_model_is_available

  # Returns OpenAI accounts ready to create an AI generation.
  #
  # @return [ActiveRecord::Relation<AiProviderConnection>] ready accounts with a selected model
  def self.ready_for_script_generation
    where(provider: "openai", status: :ready)
      .where.not(selected_model: [ nil, "" ])
      .order(:created_at, :id)
  end

  private

  def selected_model_is_available
    return if selected_model.blank?

    available_model_slugs = Array(available_models).filter_map do |available_model|
      available_model["slug"] if available_model.is_a?(Hash)
    end
    return if available_model_slugs.include?(selected_model)

    errors.add(:selected_model, "không thuộc danh sách model của kết nối")
  end
end
