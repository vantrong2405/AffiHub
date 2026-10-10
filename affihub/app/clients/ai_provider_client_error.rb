class AiProviderClientError < StandardError
  attr_reader :code

  # Initializes a sanitized error shared by external AI provider clients.
  #
  # @param code [String] the provider error category safe to expose internally
  # @return [AiProviderClientError] the provider client error
  def initialize(code)
    @code = code
    super(code)
  end
end
