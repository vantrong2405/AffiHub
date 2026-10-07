# frozen_string_literal: true

class AiGenerationEstimates::CreateService < ApplicationService
  CATEGORIES = %i[llm stock tts_fallback].freeze
  AZURE_CONFIGURATION = Rails.application.config_for(:azure_speech).deep_symbolize_keys
  attr_reader :model_id, :scenes, :input_snapshot, :scene_estimates, :cost_breakdown, :total_amount,
    :required_costs_known

  # Initializes an estimate request for the exact scene inputs.
  #
  # @param model_id [String] the MuAPI model identifier
  # @param scenes [Array<Hash>] the prompts, durations, resolutions, and aspect ratios
  # @param input_snapshot [Hash] the full generation input tied to this estimate
  # @param provider_costs [Hash] available LLM, stock, and TTS fallback costs
  # @return [AiGenerationEstimates::CreateService] the configured service
  def initialize(model_id:, scenes:, input_snapshot: {}, provider_costs: {})
    @model_id = model_id
    @scenes = scenes.map(&:symbolize_keys)
    @input_snapshot = input_snapshot.deep_symbolize_keys
    @provider_costs = default_provider_costs.merge(provider_costs.deep_symbolize_keys)
    @scene_estimates = []
    super()
  end

  # Estimates each scene and builds the provider cost breakdown.
  #
  # @return [Boolean] whether the estimate breakdown was created
  def call
    return step_fail!("Cần ít nhất một cảnh để lấy báo giá.") if scenes.empty?
    return false unless step_estimate_scenes

    build_cost_breakdown
    step_succeed!
    success?
  end

  private

  def step_estimate_scenes
    scenes.each_with_index do |scene, index|
      @scene_estimates << estimate_scene(scene, index + 1)
    end
    true
  end

  def estimate_scene(scene, scene_number)
    response = Muapi::Client.new.estimate_cost(
      model_id:,
      prompt: scene.fetch(:prompt),
      duration: scene.fetch(:duration),
      resolution: scene.fetch(:resolution),
      aspect_ratio: scene.fetch(:aspect_ratio)
    )
    {
      scene_number:,
      model_id:,
      prompt: scene.fetch(:prompt),
      duration: scene.fetch(:duration),
      resolution: scene.fetch(:resolution),
      aspect_ratio: scene.fetch(:aspect_ratio),
      amount: normalized_amount(response["cost"]),
      currency: response["currency"],
      source: "MuAPI estimate-cost",
      estimated_at: Time.current
    }
  rescue Muapi::Client::Error, KeyError
    {
      scene_number:,
      model_id:,
      prompt: scene[:prompt],
      duration: scene[:duration],
      resolution: scene[:resolution],
      aspect_ratio: scene[:aspect_ratio],
      amount: nil,
      currency: nil,
      source: "unknown",
      estimated_at: Time.current
    }
  end

  def build_cost_breakdown
    muapi_amount = sum_known_amounts(scene_estimates)
    category_costs = CATEGORIES.index_with { |category| @provider_costs.fetch(category) }
    known_costs = [ *category_costs.values, muapi_cost_record(muapi_amount) ]
    unknown_categories = CATEGORIES.select { |category| cost_amount(category_costs.fetch(category)).nil? }
    unknown_categories << :muapi if muapi_amount.nil?
    unknown_categories << :currency unless consistent_currency?(known_costs)
    currency = common_currency(known_costs)
    unknown_cost = {
      amount: unknown_categories.empty? ? "0.00" : nil,
      currency:,
      provider: "unknown",
      source: unknown_categories.empty? ? "none" : unknown_categories.join(","),
      estimated_at: Time.current
    }
    @cost_breakdown = {
      muapi: {
        amount: muapi_amount&.to_s("F"),
        currency: scene_estimates.first.fetch(:currency),
        provider: "MuAPI",
        source: "estimate-cost",
        estimated_at: Time.current,
        scenes: scene_estimates
      },
      llm: category_costs.fetch(:llm),
      stock: category_costs.fetch(:stock),
      tts_fallback: tts_fallback_cost_record,
      unknown: unknown_cost
    }
    @required_costs_known = unknown_categories.empty?
    @total_amount = required_costs_known ? sum_known_amounts(cost_breakdown.values) : nil
  end

  def default_provider_costs
    {
      llm: unknown_provider_cost("LLM"),
      stock: {
        amount: "0.00",
        currency: "USD",
        provider: "Pexels",
        source: "Pexels API license",
        estimated_at: Time.current
      },
      tts_fallback: unknown_provider_cost("TTS fallback")
    }
  end

  def tts_fallback_cost_record
    cost_record = @provider_costs.fetch(:tts_fallback)
    return cost_record if cost_record.key?(:input_snapshot)

    cost_record.merge(
      input_snapshot: {
        narration: @input_snapshot[:video_script],
        voice: AZURE_CONFIGURATION.fetch(:voice)
      }
    )
  end

  def unknown_provider_cost(provider)
    {
      amount: nil,
      currency: "USD",
      provider:,
      source: "unknown",
      estimated_at: nil
    }
  end

  def normalized_amount(amount)
    return if amount.nil?

    BigDecimal(amount.to_s)
  rescue ArgumentError
    nil
  end

  def cost_amount(cost)
    normalized_amount(cost[:amount])
  end

  def muapi_cost_record(amount)
    {
      amount: amount&.to_s("F"),
      currency: scene_estimates.first&.fetch(:currency, nil)
    }
  end

  def consistent_currency?(costs)
    currencies = costs.filter_map do |cost|
      cost[:currency] if cost_amount(cost)
    end.uniq
    currencies.length == 1 && costs.all? do |cost|
      cost_amount(cost).nil? || cost[:currency].present?
    end
  end

  def common_currency(costs)
    currencies = costs.filter_map do |cost|
      cost[:currency] if cost_amount(cost)
    end.uniq
    currencies.one? ? currencies.first : nil
  end

  def sum_known_amounts(costs)
    return unless consistent_currency?(costs)

    amounts = costs.filter_map { |cost| cost_amount(cost) }
    return if amounts.empty? || costs.any? { |cost| cost_amount(cost).nil? }

    amounts.sum(BigDecimal("0"))
  end
end
