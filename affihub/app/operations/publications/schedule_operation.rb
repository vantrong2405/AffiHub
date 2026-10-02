# frozen_string_literal: true

class Publications::ScheduleOperation < MainOperation
  attr_reader :publication, :scheduled_at

  # @param params [Hash] :current_user, :id and :scheduled_at
  # @return [void]
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
    @publication_id = params[:id]
    @scheduled_at = parse_time(params[:scheduled_at])
  end

  # Validates a future time, atomically claims the draft, and enqueues at that time.
  #
  # @return [void]
  def call
    step_load_publication
    return if error?

    step_validate_time
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

  # Rejects absent or past scheduling times.
  #
  # @return [void]
  def step_validate_time
    errors.add(:base, "Thời gian đăng phải ở thời điểm trong tương lai") unless @scheduled_at && @scheduled_at > Time.current
  end

  # Claims draft→scheduled and enqueues the job at the requested time.
  #
  # @return [void]
  def step_claim_and_enqueue
    ActiveRecord::Base.transaction do
      claimed = owned_publications.where(id: @publication_id, status: :draft).update_all(
        status: Publication.statuses.fetch("scheduled"),
        scheduled_at: @scheduled_at,
        updated_at: Time.current
      )
      errors.add(:base, "Publication không còn ở trạng thái draft") if claimed.zero?
      PublishJob.set(wait_until: @scheduled_at).perform_later(@publication_id) if claimed.positive?
    end
    @publication.reload
  end

  # Returns Publications belonging to the current user through Content ownership.
  #
  # @return [ActiveRecord::Relation<Publication>] scoped publication relation
  def owned_publications
    Publication.joins(:content).where(contents: { user_id: current_user&.id })
  end

  # Parses a request time value using the current Rails time zone.
  #
  # @param value [String, Time, nil] submitted schedule time
  # @return [Time, nil] parsed timestamp
  def parse_time(value)
    return value if value.is_a?(Time)
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
