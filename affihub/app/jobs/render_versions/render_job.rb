class RenderVersions::RenderJob < ApplicationJob
  queue_as :default

  # Renders the persisted version outside the web request.
  #
  # @param render_version_id [Integer] the version to render
  # @return [Boolean] whether the render completed successfully
  def perform(render_version_id)
    RenderVersions::RenderService.new(render_version_id:).call
  end
end
