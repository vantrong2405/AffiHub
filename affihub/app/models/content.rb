# frozen_string_literal: true

class Content < ApplicationRecord
  class InvalidTransitionError < StandardError; end

  belongs_to :product
  belongs_to :user

  enum :status, { generated: "generated", review: "review", approved: "approved", rejected: "rejected" }, prefix: true

  # Moves generated content into the review lifecycle state.
  #
  # @return [Boolean] true after the status is persisted
  # @raise [Content::InvalidTransitionError] when the content is not generated
  def start_review!
    return update!(status: :review) if status_generated? || status_rejected?

    raise InvalidTransitionError
  end

  # Approves reviewed content for publication.
  #
  # @return [Boolean] true after the status is persisted
  # @raise [Content::InvalidTransitionError] when the content is not under review
  def approve!
    transition_status!(from: :review, to: :approved)
  end

  # Rejects reviewed content without allowing it to be published.
  #
  # @return [Boolean] true after the status is persisted
  # @raise [Content::InvalidTransitionError] when the content is not under review
  def reject!
    transition_status!(from: :review, to: :rejected)
  end

  private

  # Persists a lifecycle transition only when the content is in the expected source state.
  #
  # @param from [Symbol] required source status
  # @param to [Symbol] target status
  # @return [Boolean] true after the target status is persisted
  # @raise [Content::InvalidTransitionError] when the current status differs from from
  def transition_status!(from:, to:)
    raise InvalidTransitionError unless status == from.to_s

    update!(status: to)
  end
end
