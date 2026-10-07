class SourceAssets::InspectJob < ApplicationJob
  # Inspects an attached source video outside the web request.
  #
  # @param source_asset_id [Integer] the source to inspect
  # @return [Boolean] whether media inspection succeeded
  def perform(source_asset_id)
    SourceAssets::InspectService.new(source_asset_id:).call
  end
end
