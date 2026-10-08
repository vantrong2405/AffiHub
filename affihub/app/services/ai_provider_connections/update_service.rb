class AiProviderConnections::UpdateService < ApplicationService
  # Initializes a model-selection update for one provider account.
  #
  # @param ai_provider_connection_id [String, Integer] the connected provider account ID
  # @param selected_model [String] the model slug selected from this account's catalog
  # @return [AiProviderConnections::UpdateService] the configured service
  def initialize(ai_provider_connection_id:, selected_model:)
    @ai_provider_connection_id = ai_provider_connection_id
    @selected_model = selected_model.to_s
    super()
  end

  # Saves a model that belongs to the selected provider account.
  #
  # @return [Boolean] whether the model selection was saved
  def call
    return false unless step_load_connection
    return false unless step_validate_model

    @ai_provider_connection.selected_model = @selected_model
    return step_succeed! if @ai_provider_connection.save

    step_fail!("Model này không có trong danh sách của kết nối.")
  end

  private

  def step_load_connection
    @ai_provider_connection = AiProviderConnection.find_by(id: @ai_provider_connection_id)
    return true if @ai_provider_connection

    step_fail!("Không tìm thấy kết nối tài khoản AI.")
  end

  def step_validate_model
    available_model_slugs = @ai_provider_connection.available_models.filter_map do |available_model|
      available_model["slug"] if available_model.is_a?(Hash)
    end
    return true if available_model_slugs.include?(@selected_model)

    step_fail!("Model này không có trong danh sách của kết nối.")
  end
end
