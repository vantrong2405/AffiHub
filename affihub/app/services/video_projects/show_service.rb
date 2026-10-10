class VideoProjects::ShowService < ApplicationService
  # @return [VideoProject] the selected project
  attr_reader :video_project

  # @return [Array<SourceAsset>] the project's source assets
  attr_reader :source_assets

  # @return [Array<RenderVersion>] the project's render versions
  attr_reader :render_versions

  # @return [Array<AiGeneration>] the project's recent AI generations
  attr_reader :ai_generations

  # Initializes a project workspace query.
  #
  # @param video_project_id [Integer] the project to display
  # @return [VideoProjects::ShowService] the configured service
  def initialize(video_project_id:)
    @video_project_id = video_project_id
    super()
  end

  # Loads the project and its local media history.
  #
  # @return [Boolean] whether the workspace was loaded
  def call
    step_load_video_project
    step_load_source_assets
    step_load_render_versions
    step_load_ai_generations
    step_succeed!
    success?
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find(@video_project_id)
  end

  def step_load_source_assets
    @source_assets = video_project.source_assets.with_attached_file.recent_first.to_a
  end

  def step_load_render_versions
    @render_versions = video_project.render_versions.with_attached_file.recent_first.to_a
  end

  def step_load_ai_generations
    @ai_generations = video_project.ai_generations.recent_first.to_a
  end
end
