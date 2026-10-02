# frozen_string_literal: true

class PublishJob < ApplicationJob
  queue_as :default

  # Atomically claims and publishes a scheduled Publication, recording provider results.
  #
  # @param publication_id [Integer] Publication primary key
  # @return [void]
  def perform(publication_id)
    claimed = Publication.where(id: publication_id, status: :scheduled).update_all(
      status: Publication.statuses.fetch("publishing"),
      last_attempt_at: Time.current,
      updated_at: Time.current
    )
    return if claimed.zero?

    @publication = Publication.find(publication_id)
    result = PublisherResolver.resolve(@publication.social_destination).new.publish(@publication)
    persist_result(result)
  rescue StandardError => error
    record_unexpected_failure(error) if @publication
  end

  private

  # Persists the complete provider result in one update.
  #
  # @param result [MetaGraphPublisher::Result] parsed provider outcome
  # @return [void]
  def persist_result(result)
    @publication.update!(
      status: result.success ? :published : :failed,
      provider_post_id: result.provider_post_id,
      published_url: result.published_url,
      published_at: result.published_at,
      error_code: result.error_code,
      error_message: result.error_message,
      provider_metadata: result.provider_metadata || {},
      attempt_count: @publication.attempt_count + 1
    )
  end

  # Logs unexpected errors and marks the outcome ambiguous without leaving Publishing stuck.
  #
  # @param error [StandardError] unexpected publisher or persistence error
  # @return [void]
  def record_unexpected_failure(error)
    destination = @publication.social_destination
    Rails.logger.error(
      "publication_id=#{@publication.id} exception_class=#{error.class.name} " \
      "exception_message=#{error.message.inspect} backtrace=#{error.backtrace.inspect} " \
      "page_id=#{destination&.page_id}"
    )
    @publication.update!(
      status: :failed,
      error_code: "internal_error",
      error_message: error.message,
      attempt_count: @publication.attempt_count + 1
    )
  end
end
