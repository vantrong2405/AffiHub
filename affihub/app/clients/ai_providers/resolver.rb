# frozen_string_literal: true

class AIProviders::Resolver
  # Returns the sole provider adapter enabled by the current POC.
  #
  # @return [AIProviders::Contract] configured AI provider contract
  def self.default
    AIProviders::CodexAdapter.new
  end
end
