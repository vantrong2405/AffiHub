# frozen_string_literal: true

class AiGenerations::NewService < ApplicationService
  attr_reader :video_project, :create_form

  # Initializes a project-scoped AI generation form.
  #
  # @param video_project_id [Integer] the project receiving the generation
  # @return [AiGenerations::NewService] the configured service
  def initialize(video_project_id:)
    @video_project_id = video_project_id
    super()
  end

  # Loads the project and its configured generation defaults.
  #
  # @return [Boolean] whether the form data was loaded
  def call
    step_load_video_project
    step_build_create_form
    step_succeed!
    success?
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find(@video_project_id)
  end

  def step_build_create_form
    @create_form = AiGenerations::CreateForm.new
  end
end
