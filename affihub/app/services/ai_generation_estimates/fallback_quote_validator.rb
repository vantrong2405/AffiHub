# frozen_string_literal: true

class AiGenerationEstimates::FallbackQuoteValidator
  CONFIGURATION = Rails.application.config_for(:azure_speech).deep_symbolize_keys

  # Initializes validation for one Azure fallback quote and its approved input.
  #
  # @param quote [Hash] the Azure quote saved with the generation
  # @param narration [String] the approved narration text
  # @param voice [String] the approved Azure voice
  # @param currency [String] the generation's approved estimate currency
  # @return [AiGenerationEstimates::FallbackQuoteValidator] the configured validator
  def initialize(quote:, narration:, voice:, currency:)
    @quote = quote.is_a?(Hash) ? quote.deep_symbolize_keys : {}
    @narration = narration
    @voice = voice
    @currency = currency
  end

  # Checks that the quote is current and matches the approved narration and voice.
  #
  # @return [Boolean] whether the quote can authorize Azure fallback
  def valid?
    return false unless azure_provider?
    return false unless quote_matches_input?
    return false unless @quote[:currency] == @currency && @quote[:source].present?

    amount = BigDecimal(@quote[:amount].to_s)
    estimated_at = quote_estimated_at
    amount.finite? && amount.positive? && estimated_at <= Time.current &&
      Time.current - estimated_at <= CONFIGURATION.fetch(:estimate_max_age_seconds).to_i.seconds
  rescue ArgumentError, KeyError, TypeError
    false
  end

  private

  def azure_provider?
    @quote[:provider].to_s.downcase.gsub(/\s+/, "_") == "azure_speech"
  end

  def quote_matches_input?
    input_snapshot = @quote[:input_snapshot]
    return false unless input_snapshot.is_a?(Hash)

    input_snapshot.deep_symbolize_keys == { narration: @narration, voice: @voice }
  end

  def quote_estimated_at
    estimated_at = @quote[:estimated_at]
    return estimated_at.to_time if estimated_at.respond_to?(:to_time)

    Time.iso8601(estimated_at.to_s)
  end
end
