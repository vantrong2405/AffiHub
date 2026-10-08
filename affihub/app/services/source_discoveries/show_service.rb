class SourceDiscoveries::ShowService < ApplicationService
  DISCOVERY_CONFIGURATION = Rails.application.config_for(:youtube).deep_symbolize_keys.fetch(:discovery)

  # @return [VideoProject] the project that owns the search
  attr_reader :video_project

  # @return [SourceDiscovery] the selected search and its results
  attr_reader :source_discovery

  # @return [Hash] configured YouTube regions and their Vietnamese labels
  attr_reader :regions

  # @return [Hash] configured YouTube categories and their Vietnamese labels
  attr_reader :video_categories

  # Initializes a project-scoped discovery result query.
  #
  # @param video_project_id [Integer] the project that owns the search
  # @param source_discovery_id [Integer] the saved search to display
  # @return [SourceDiscoveries::ShowService] the configured service
  def initialize(video_project_id:, source_discovery_id:)
    @video_project_id = video_project_id
    @source_discovery_id = source_discovery_id
    @regions = DISCOVERY_CONFIGURATION.fetch(:regions)
    @video_categories = DISCOVERY_CONFIGURATION.fetch(:video_categories)
    super()
  end

  # Loads the saved search and its YouTube metadata results.
  #
  # @return [Boolean] whether the result page was loaded
  def call
    step_load_video_project
    step_load_source_discovery
    step_succeed!
    success?
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find(@video_project_id)
  end

  def step_load_source_discovery
    @source_discovery = video_project.source_discoveries
      .includes(source_discovery_results: :youtube_discovery_metadata)
      .find(@source_discovery_id)
  end
end
