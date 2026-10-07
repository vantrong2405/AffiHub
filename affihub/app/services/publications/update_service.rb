class Publications::UpdateService < ApplicationService
  attr_reader :publication

  # Initializes a caption update for one draft Publication.
  #
  # @param publication_id [Integer] the draft to update
  # @param caption [String] the destination-specific caption
  # @return [Publications::UpdateService] the configured service
  def initialize(publication_id:, caption:)
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
      @publication = Publication.lock.find_by(id: @publication_id)
      return step_fail!("Không tìm thấy Publication.") unless publication
      return step_fail!("Chỉ được sửa caption khi Publication còn là bản nháp.") unless publication.draft?
      return true if publication.update(caption: @caption)

      step_fail!(publication.errors.full_messages.to_sentence)
    end
  end
end
