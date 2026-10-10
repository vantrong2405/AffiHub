class Youtube::QuotaReservationService < ApplicationService
  attr_reader :counter, :observed_count, :daily_limit

  # Initializes a local reservation for one YouTube API quota bucket.
  #
  # @param bucket [String, Symbol] configured operation key such as search_list
  # @return [Youtube::QuotaReservationService] the configured service
  def initialize(bucket:)
    @bucket_key = bucket.to_sym
    super()
  end

  # Reserves one AffiHub request slot if the configured local bucket has capacity.
  #
  # @return [Boolean] whether the request may proceed
  def call
    return false unless step_load_bucket

    step_reserve_request
    success?
  end

  private

  def step_load_bucket
    configuration = Rails.application.config_for(:youtube).deep_symbolize_keys.fetch(:quota)
    bucket = configuration.fetch(:buckets).fetch(@bucket_key)
    @bucket = bucket.fetch(:method).to_s
    @daily_limit = bucket.fetch(:daily_limit).to_i
    @usage_date = Time.current.in_time_zone(configuration.fetch(:timezone)).to_date
    @initial_count = configuration.fetch(:counter_initial_count).to_i
    return step_fail!("Giới hạn quota YouTube chưa được cấu hình hợp lệ.") unless @daily_limit.positive?

    true
  rescue KeyError
    step_fail!("Thao tác YouTube này chưa có bucket quota được cấu hình.")
  end

  def step_reserve_request
    @counter = YoutubeQuotaCounter.create_or_find_by!(bucket: @bucket, usage_date: @usage_date) do |counter|
      counter.requests_count = @initial_count
    end
    @counter.with_lock do
      @observed_count = @counter.requests_count
      return step_fail!("Quota local cho #{@bucket} đã hết trong ngày theo giờ Pacific.") if @observed_count >= @daily_limit

      @counter.update!(requests_count: @observed_count + 1)
      @observed_count += 1
      step_succeed!
    end
  rescue ActiveRecord::RecordInvalid
    step_fail!("Không thể ghi nhận quota request của YouTube.")
  end
end
