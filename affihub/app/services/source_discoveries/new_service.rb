class SourceDiscoveries::NewService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:youtube).deep_symbolize_keys
  DISCOVERY_CONFIGURATION = CONFIGURATION.fetch(:discovery)

  # @return [VideoProject] the project receiving a new discovery search
  attr_reader :video_project

  # @return [SourceDiscovery] the form's search values
  attr_reader :source_discovery

  # @return [Hash] configured YouTube regions and their Vietnamese labels
  attr_reader :regions

  # @return [Hash] configured YouTube categories and their Vietnamese labels
  attr_reader :video_categories

  # @return [String] the default region for keyword search
  attr_reader :default_region_code

  # Initializes the YouTube discovery form query.
  #
  # @param video_project_id [Integer] the project that owns the search
  # @return [SourceDiscoveries::NewService] the configured service
  def initialize(video_project_id:)
    @video_project_id = video_project_id
    @regions = DISCOVERY_CONFIGURATION.fetch(:regions)
    @video_categories = DISCOVERY_CONFIGURATION.fetch(:video_categories)
    @default_region_code = CONFIGURATION.fetch(:default_region_code).to_s
    @source_discovery = SourceDiscovery.new(
      search_type: DISCOVERY_CONFIGURATION.fetch(:search_types).fetch(:keyword),
      region_code: @default_region_code
    )
    super()
  end

  # Loads the owning project and available search options.
  #
  # @return [Boolean] whether the form is ready to render
  def call
    step_load_video_project
    step_succeed!
    success?
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find(@video_project_id)
  end
end
