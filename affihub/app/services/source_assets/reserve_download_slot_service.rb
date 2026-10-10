class SourceAssets::ReserveDownloadSlotService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:source_download)
  GLOBAL_GATE_KEY = "global"

  # @return [ActiveSupport::TimeWithZone, nil] the next time a start is available
  attr_reader :next_available_at

  # Initializes an atomic reservation for one configured download start.
  #
  # @return [SourceAssets::ReserveDownloadSlotService] the configured service
  def initialize
    super()
  end

  # Reserves a downloader start inside the configured rolling window.
  #
  # @return [Boolean] whether a new download start was reserved
  def call
    step_reserve_slot
    success?
  end

  private

  def step_reserve_slot
    now = Time.current
    gate = SourceDownloadGate.create_or_find_by!(key: GLOBAL_GATE_KEY)
    gate.with_lock do
      window_seconds = CONFIGURATION.fetch(:window_seconds)
      window_start = now - window_seconds.seconds
      active_slots = SourceDownloadSlot.where(started_at: window_start..now)
      active_count = active_slots.count
      if active_count >= CONFIGURATION.fetch(:max_starts_per_window)
        step_set_next_available_at(active_slots, active_count, window_seconds)
        step_fail!("Đã chạm giới hạn số lượt tải trong giờ vừa qua.")
      else
        SourceDownloadSlot.create!(started_at: now)
        step_succeed!
      end
    end
  end

  def step_set_next_available_at(active_slots, active_count, window_seconds)
    index_to_expire = active_count - CONFIGURATION.fetch(:max_starts_per_window)
    next_slot_expiry = active_slots.order(:started_at, :id).offset(index_to_expire).pick(:started_at)
    @next_available_at = next_slot_expiry + window_seconds.seconds
  end
end
