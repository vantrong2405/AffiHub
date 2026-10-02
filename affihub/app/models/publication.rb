# frozen_string_literal: true

class Publication < ApplicationRecord
  STALE_PUBLISHING_AFTER = 10.minutes

  serialize :provider_metadata, coder: JSON, type: Hash

  belongs_to :content
  belongs_to :social_destination

  enum :status, {
    draft: "draft",
    scheduled: "scheduled",
    publishing: "publishing",
    published: "published",
    failed: "failed"
  }, prefix: true

  # Reports whether a retry could duplicate a post Meta may already have accepted.
  #
  # @return [Boolean] true when the provider outcome is ambiguous
  def ambiguous_outcome?
    status_publishing? || (status_failed? && error_code == "internal_error")
  end
end
