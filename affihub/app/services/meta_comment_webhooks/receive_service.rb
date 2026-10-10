class MetaCommentWebhooks::ReceiveService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:auto_responder)
  META_CONFIGURATION = Rails.application.config_for(:meta).deep_symbolize_keys.fetch(:providers)

  attr_reader :http_status

  # Initializes a raw Meta comment webhook delivery.
  #
  # @param raw_body [String] the unparsed HTTP request body used for signature validation
  # @param signature [String] Meta's X-Hub-Signature-256 header value
  # @return [MetaCommentWebhooks::ReceiveService] the configured service
  def initialize(raw_body:, signature:)
    @raw_body = raw_body.to_s
    @signature = signature.to_s
    @http_status = :ok
    super()
  end

  # Verifies, filters, persists, and queues the public comment events in a delivery.
  #
  # @return [Boolean] whether the delivery was accepted
  def call
    step_verify_signature
    return false unless success?

    step_parse_payload
    return false unless success?

    step_receive_comments
    success?
  end

  private

  def step_verify_signature
    app_secret = Rails.application.credentials.dig(:meta, :app_secret).to_s
    return step_reject(:unauthorized, "Chưa cấu hình Meta App Secret.") if app_secret.blank?
    return step_reject(:unauthorized, "Chữ ký webhook Meta không đúng định dạng.") unless @signature.start_with?("sha256=")

    supplied_signature = @signature.delete_prefix("sha256=")
    expected_signature = OpenSSL::HMAC.hexdigest("SHA256", app_secret, @raw_body)
    return step_reject(:unauthorized, "Không xác minh được chữ ký webhook Meta.") unless step_secure_signature_match?(
      expected_signature,
      supplied_signature
    )

    step_succeed!
  end

  def step_parse_payload
    @payload = JSON.parse(@raw_body)
    return step_reject(:bad_request, "Payload webhook Meta không hợp lệ.") unless @payload.is_a?(Hash)

    step_succeed!
  rescue JSON::ParserError
    step_reject(:bad_request, "Payload webhook Meta không phải JSON hợp lệ.")
  end

  def step_receive_comments
    provider = step_provider_for_payload
    return step_succeed! unless provider

    Array(@payload["entry"]).each do |entry|
      step_receive_entry(provider, entry) if entry.is_a?(Hash)
    end
    step_succeed!
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => error
    step_reject(:internal_server_error, error.message)
  end

  def step_provider_for_payload
    META_CONFIGURATION.find do |_provider, configuration|
      configuration.fetch(:comment_webhook_object, nil) == @payload["object"]
    end&.first
  end

  def step_receive_entry(provider, entry)
    destination = SocialDestination.find_by(provider: provider.to_s, external_id: entry["id"])
    return unless destination
    return unless step_default_rule_enabled?(destination)

    Array(entry["changes"]).each do |change|
      attributes = step_comment_attributes(provider, destination, entry, change)
      step_persist_comment(destination, attributes) if attributes
    end
  end

  def step_default_rule_enabled?(destination)
    destination.auto_reply_rules.exists?(
      rule_type: CONFIGURATION.fetch(:default_rule_type),
      enabled: true
    )
  end

  def step_comment_attributes(provider, destination, entry, change)
    return unless change.is_a?(Hash)

    provider_configuration = META_CONFIGURATION.fetch(provider)
    return unless change["field"] == provider_configuration.fetch(:comment_webhook_field)

    value = change["value"]
    return unless value.is_a?(Hash)

    if provider == :facebook
      step_facebook_comment_attributes(provider, destination, entry, value)
    else
      step_instagram_comment_attributes(provider, destination, value)
    end
  end

  def step_facebook_comment_attributes(provider, destination, entry, value)
    return unless value["item"] == "comment" && value["verb"] == "add"

    sender = value["from"]
    return unless sender.is_a?(Hash) && sender["id"].present?
    return if sender["id"].to_s == entry["id"].to_s

    step_build_comment_attributes(provider, destination, value["comment_id"], value["message"])
  end

  def step_instagram_comment_attributes(provider, destination, value)
    return if value["parent_id"].present?

    sender = value["from"]
    self_ig_scoped_id = value["self_ig_scoped_id"]
    return unless sender.is_a?(Hash) && sender["id"].present? && self_ig_scoped_id.present?
    return if sender["id"].to_s == self_ig_scoped_id.to_s

    step_build_comment_attributes(provider, destination, value["id"], value["text"])
  end

  def step_build_comment_attributes(provider, destination, comment_id, comment_text)
    return if destination.external_id.blank?
    return unless comment_id.is_a?(String) && comment_id.present?
    return unless comment_text.is_a?(String) && comment_text.present?

    {
      social_destination_id: destination.id,
      source: provider.to_s,
      event_type: CONFIGURATION.fetch(:comment_event_type),
      provider_comment_id: comment_id,
      comment_text: comment_text
    }
  end

  def step_persist_comment(destination, attributes)
    service = AutoResponder::ReceiveCommentService.new(**attributes.merge(social_destination_id: destination.id))
    return if service.call

    raise ActiveRecord::RecordInvalid, service
  end

  def step_secure_signature_match?(expected_signature, supplied_signature)
    return false if expected_signature.blank? || supplied_signature.blank?
    return false unless expected_signature.bytesize == supplied_signature.bytesize

    ActiveSupport::SecurityUtils.secure_compare(expected_signature, supplied_signature)
  end

  def step_reject(status, message)
    @http_status = status
    step_fail!(message)
  end
end
