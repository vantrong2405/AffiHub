class Schedules::CreateForm
  attr_reader :render_version_id, :preflight_report_id, :scheduled_at, :time_zone, :recurrence,
    :destination_ids, :destination_captions, :destination_ids_submitted

  # Normalizes the submitted Schedule form values.
  #
  # @param attributes [Hash, ActionController::Parameters] submitted form fields
  # @return [Schedules::CreateForm] the normalized form
  def initialize(attributes = {})
    attributes = attributes.to_h.symbolize_keys
    @render_version_id = attributes[:render_version_id]
    @preflight_report_id = attributes[:preflight_report_id]
    @scheduled_at = attributes[:scheduled_at]
    @time_zone = attributes[:time_zone]
    @recurrence = attributes[:recurrence]
    @destination_ids_submitted = attributes.key?(:destination_ids)
    @destination_ids = Array(attributes[:destination_ids]).reject(&:blank?).map(&:to_s)
    @destination_captions = attributes.fetch(:destination_captions, {}).to_h.stringify_keys
  end

  # Builds per-destination captions and copies consent from the matching draft.
  #
  # @param publications_by_destination [Hash{String => Publication}] saved drafts by destination ID
  # @return [Hash{String => Hash}] settings passed to the Schedule creation service
  def destination_settings(publications_by_destination)
    destination_ids.uniq.index_with do |destination_id|
      publication = publications_by_destination[destination_id]
      {
        "caption" => destination_captions.fetch(destination_id, publication&.caption.to_s),
        "consent_snapshot" => publication&.consent_snapshot.to_h.stringify_keys || {}
      }
    end
  end

  # Reports whether the form submitted an explicit destination selection.
  #
  # @return [Boolean] whether destination IDs appeared in the submitted fields
  def destination_ids_submitted?
    destination_ids_submitted
  end
end
