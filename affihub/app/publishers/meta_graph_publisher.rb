# frozen_string_literal: true

class MetaGraphPublisher
  Result = Data.define(:success, :provider_post_id, :published_url, :published_at, :error_code, :error_message, :provider_metadata) do
    # Builds a successful provider result after Meta confirms a post.
    #
    # @param provider_post_id [String] id returned by Meta
    # @param published_url [String, nil] permalink resolved from Meta
    # @param published_at [Time] confirmation time
    # @param provider_metadata [Hash] selected debugging fields
    # @return [MetaGraphPublisher::Result] successful result
    def self.success(provider_post_id:, published_url:, published_at:, provider_metadata: {})
      new(true, provider_post_id, published_url, published_at, nil, nil, provider_metadata)
    end

    # Builds a failed result from a structured Meta API error response.
    #
    # @param error_code [String] provider error code
    # @param error_message [String] provider error message
    # @param provider_metadata [Hash] selected debugging fields
    # @return [MetaGraphPublisher::Result] failed result
    def self.failure(error_code:, error_message:, provider_metadata: {})
      new(false, nil, nil, nil, error_code, error_message, provider_metadata)
    end
  end

  # @param client [MetaGraphClient] official Meta Graph API boundary
  # @return [void]
  def initialize(client: MetaGraphClient.new)
    @client = client
  end

  # Publishes an approved Content to its selected Facebook Page.
  #
  # @param publication [Publication] publication currently claimed by a PublishJob
  # @return [MetaGraphPublisher::Result] provider-confirmed success or structured failure
  def publish(publication)
    content = publication.content
    destination = publication.social_destination
    response = @client.publish_post(
      page_id: destination.page_id,
      page_access_token: destination.page_access_token,
      message: "#{content.body}\n\n#{content.affiliate_url}"
    )
    post_id = response.fetch("id")
    metadata = { "fbtrace_id" => response["fbtrace_id"] }.compact
    permalink = fetch_permalink(post_id, destination.page_access_token, metadata)

    Result.success(
      provider_post_id: post_id,
      published_url: permalink,
      published_at: Time.current,
      provider_metadata: metadata
    )
  rescue MetaGraphClient::ApiError => error
    raise error if error.code.nil?

    metadata = { "fbtrace_id" => error.trace_id }.compact
    Result.failure(error_code: error.code.to_s, error_message: error.message, provider_metadata: metadata)
  end

  private

  # Fetches a permalink without undoing provider-confirmed publication success.
  #
  # @param post_id [String] post id returned by publish
  # @param page_access_token [String] token for the selected Page
  # @param metadata [Hash] provider metadata to update on permalink failure
  # @return [String, nil] permalink or nil when lookup fails
  def fetch_permalink(post_id, page_access_token, metadata)
    @client.fetch_permalink_url(post_id:, page_access_token:)
  rescue MetaGraphClient::ApiError, MetaGraphClient::TransportError
    metadata["permalink_fetch_failed"] = true
    nil
  end
end
