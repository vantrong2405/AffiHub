class Publications::QuotaReservationService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:publication_quota)

  attr_reader :publication, :reservation, :next_available_at

  # Initializes a quota reservation for one Publication and destination.
  #
  # @param publication_id [Integer] the Publication that may start publishing
  # @return [Publications::QuotaReservationService] the configured service
  def initialize(publication_id:)
    @publication_id = publication_id
    super()
  end

  # Reserves one destination slot for a new Publication in the rolling window.
  #
  # @return [Boolean] whether the Publication may start its first provider request
  def call
    return false unless step_load_publication

    step_reserve_slot
    success?
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  private

  def step_load_publication
    @publication = Publication.find_by(id: @publication_id)
    return true if publication

    step_fail!("Không tìm thấy Publication cần cấp quota.")
  end

  def step_reserve_slot
    publication.social_destination.with_lock do
      @reservation = PublicationQuotaReservation.find_by(publication_id: publication.id)
      return step_succeed! if reservation

      active_reservations = step_active_reservations
      return step_reject_full_window(active_reservations) if active_reservations.size >= max_per_destination

      @reservation = PublicationQuotaReservation.create!(
        publication:,
        social_destination: publication.social_destination,
        reserved_at: Time.current
      )
      step_succeed!
    end
  end

  def step_active_reservations
    window_start = Time.current - window_seconds.seconds
    PublicationQuotaReservation.where(social_destination: publication.social_destination)
      .where(reserved_at: window_start...Time.current)
      .order(:reserved_at, :id)
  end

  def step_reject_full_window(active_reservations)
    index_to_expire = active_reservations.size - max_per_destination
    @next_available_at = active_reservations.offset(index_to_expire).pick(:reserved_at) + window_seconds.seconds
    step_fail!("Destination đã dùng đủ quota publish; lượt tiếp theo mở lúc #{next_available_at.iso8601}.")
  end

  def max_per_destination
    CONFIGURATION.fetch(:max_per_destination).to_i
  end

  def window_seconds
    CONFIGURATION.fetch(:window_seconds).to_i
  end
end
