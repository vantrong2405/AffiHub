# frozen_string_literal: true

class PublisherResolver
  REGISTRY = { [ "facebook", "page" ] => MetaGraphPublisher }.freeze

  # Resolves a Publisher class for a concrete social destination.
  #
  # @param destination [SocialDestination] selected publication destination
  # @return [Class] publisher class implementing #publish
  # @raise [KeyError] when no publisher supports the destination provider/type
  def self.resolve(destination)
    provider = destination.social_connection.provider
    type = destination.destination_type
    REGISTRY.fetch([ provider, type ]) do
      raise KeyError, "No publisher registered for #{provider}/#{type}"
    end
  end
end
