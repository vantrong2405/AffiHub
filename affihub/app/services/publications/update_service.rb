class Publications::UpdateService < ApplicationService
  # The project that owns the updated Publication.
  # @return [VideoProject]
  attr_reader :video_project

  attr_reader :publication

  # Initializes a caption update for one draft Publication in a project.
  #
  # @param video_project_id [Integer] the project that owns the Publication
  # @param publication_id [Integer] the draft to update
  # @param caption [String] the destination-specific caption
  # @return [Publications::UpdateService] the configured service
  def initialize(video_project_id:, publication_id:, caption:)
    @video_project_id = video_project_id
    @publication_id = publication_id
    @caption = caption
    super()
  end

  # Updates a caption only while its Publication is still a draft.
  #
  # @return [Boolean] whether the draft caption was updated
  def call
    return false unless step_update_caption

    step_succeed!
    success?
  end

  private

  def step_update_caption
    Publication.transaction do
      @video_project = VideoProject.find(@video_project_id)
      @publication = video_project.publications.lock.find(@publication_id)
      return step_fail!("Chỉ được sửa caption khi Publication còn là bản nháp.") unless publication.draft?
      return true if publication.update(caption: @caption)

      step_fail!(publication.errors.full_messages.to_sentence)
    end
  end
end
