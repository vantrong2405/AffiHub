# frozen_string_literal: true

class Publications::PostNowOperation < MainOperation
  attr_reader :publication

  # @param params [Hash] :current_user and :id
  # @return [void]
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
    @publication_id = params[:id]
  end

  # Atomically claims an owned draft and enqueues its background publish job.
  #
  # @return [void]
  def call
    step_load_publication
    return if error?

    step_claim_and_enqueue
  end

  private

  # Loads a Publication through its owning Content.
  #
  # @return [void]
  def step_load_publication
    @publication = owned_publications.find_by(id: @publication_id)
    errors.add(:base, "Publication không tồn tại hoặc không thuộc tài khoản của bạn") unless @publication
  end

  # Claims draft→scheduled in a user-scoped update and enqueues in the same transaction.
  #
  # @return [void]
  def step_claim_and_enqueue
    ActiveRecord::Base.transaction do
      claimed = owned_publications.where(id: @publication_id, status: :draft).update_all(
        status: Publication.statuses.fetch("scheduled"),
        updated_at: Time.current
      )
      errors.add(:base, "Publication không còn ở trạng thái draft") if claimed.zero?
      PublishJob.perform_later(@publication_id) if claimed.positive?
    end
    @publication.reload
  end

  # Returns Publications belonging to the current user through Content ownership.
  #
  # @return [ActiveRecord::Relation<Publication>] scoped publication relation
  def owned_publications
    Publication.joins(:content).where(contents: { user_id: current_user&.id })
  end
end
