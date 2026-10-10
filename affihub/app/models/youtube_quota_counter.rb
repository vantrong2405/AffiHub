class YoutubeQuotaCounter < ApplicationRecord
  CONFIGURATION = Rails.application.config_for(:youtube).deep_symbolize_keys.fetch(:quota)
  BUCKETS = CONFIGURATION.fetch(:buckets).values.map { |bucket| bucket.fetch(:method).to_s }.freeze

  attribute :requests_count, default: CONFIGURATION.fetch(:counter_initial_count)

  validates :bucket, :usage_date, :requests_count, presence: true
  validates :bucket, inclusion: { in: BUCKETS }
  validates :requests_count, numericality: { only_integer: true, greater_than_or_equal_to: CONFIGURATION.fetch(:counter_initial_count) }
  validates :usage_date, uniqueness: { scope: :bucket }
end
