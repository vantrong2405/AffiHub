# frozen_string_literal: true

class Publications::RetryOperation < MainOperation
  AMBIGUOUS_RETRY_MESSAGE = "Kết quả đăng trước chưa rõ. Retry có thể tạo bài trùng; hãy xác nhận để tiếp tục."

  attr_reader :publication

  # @param params [Hash] :current_user, :id and optional :confirm_duplicate_risk
  # @return [void]
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
    @publication_id = params[:id]
    @confirmed = ActiveModel::Type::Boolean.new.cast(params[:confirm_duplicate_risk])
  end

  # Claims eligible failed or stale Publications and enqueues a new job.
  #
  # @return [void]
  def call
    step_load_publication
    return if error?

    step_validate_retry
    step_claim_and_enqueue unless error?
  end

  private

  # Loads a Publication through its owning Content.
  #
  # @return [void]
  def step_load_publication
    @publication = owned_publications.find_by(id: @publication_id)
    errors.add(:base, "Publication không tồn tại hoặc không thuộc tài khoản của bạn") unless @publication
  end

  # Checks eligibility, staleness, and duplicate-risk confirmation.
  #
  # @return [void]
  def step_validate_retry
    if @publication.status_failed?
      errors.add(:base, AMBIGUOUS_RETRY_MESSAGE) if @publication.ambiguous_outcome? && !@confirmed
    elsif @publication.status_publishing?
      errors.add(:base, "Publication đang được xử lý; hãy đợi trước khi thử lại") unless stale?
      errors.add(:base, AMBIGUOUS_RETRY_MESSAGE) if stale? && !@confirmed
    else
      errors.add(:base, "Chỉ có thể retry Publication failed hoặc publishing bị kẹt")
    end
  end

  # Claims failed or stale Publishing→scheduled and enqueues one new job.
  #
  # @return [void]
  def step_claim_and_enqueue
    ActiveRecord::Base.transaction do
      claim_scope = owned_publications.where(id: @publication_id)
      claimed = if @publication.status_failed?
        claim_scope.where(status: :failed).update_all(status: Publication.statuses.fetch("scheduled"), updated_at: Time.current)
      else
        claim_scope.where(status: :publishing).where("publications.last_attempt_at < ?", stale_cutoff)
          .update_all(status: Publication.statuses.fetch("scheduled"), updated_at: Time.current)
      end
      errors.add(:base, "Publication đã thay đổi trạng thái; tải lại trước khi retry") if claimed.zero?
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

  # Reports whether the last publishing attempt passed the stale threshold.
  #
  # @return [Boolean] true when this Publication can be retried
  def stale?
    @publication.last_attempt_at && @publication.last_attempt_at < stale_cutoff
  end

  # Computes the one shared stale cutoff for this attempt.
  #
  # @return [ActiveSupport::TimeWithZone] earliest eligible attempt time
  def stale_cutoff
    Publication::STALE_PUBLISHING_AFTER.ago
  end
end
