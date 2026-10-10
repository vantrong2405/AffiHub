class Publications::CreateForm
  # The project render selected for this draft.
  # @return [String, Integer, nil]
  attr_reader :render_version_id

  # The preflight report used to choose destinations.
  # @return [String, Integer, nil]
  attr_reader :preflight_report_id

  # The selected social destination IDs.
  # @return [Array<String>]
  attr_reader :destination_ids

  # Captions keyed by social destination ID.
  # @return [Hash{String => String}]
  attr_reader :destination_captions

  # Initializes the draft creation inputs from permitted request values.
  #
  # @param attributes [Hash, ActionController::Parameters] the permitted publication inputs
  # @return [Publications::CreateForm] the normalized form
  def initialize(attributes = {})
    attributes = attributes.to_h.symbolize_keys
    @render_version_id = attributes[:render_version_id]
    @preflight_report_id = attributes[:preflight_report_id]
    @destination_ids = Array(attributes[:destination_ids]).map(&:to_s)
    @destination_captions = attributes.fetch(:destination_captions, {}).to_h.stringify_keys
  end

  # Returns one caption for each selected destination.
  #
  # @return [Hash{String => String}] selected destination captions
  def destination_captions_for_create
    destination_ids.each_with_object({}) do |destination_id, captions|
      captions[destination_id] = destination_captions.fetch(destination_id, "")
    end
  end
end
