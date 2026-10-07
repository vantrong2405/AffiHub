class Publications::CreateService < ApplicationService
  attr_reader :publications

  # Initializes draft creation for the destinations covered by a preflight report.
  #
  # @param render_version_id [Integer] the immutable render version to publish
  # @param preflight_report_id [Integer] the report used to verify destination readiness
  # @param destination_captions [Hash] caption text keyed by social destination ID
  # @return [Publications::CreateService] the configured service
  def initialize(render_version_id:, preflight_report_id:, destination_captions:)
    @render_version_id = render_version_id
    @preflight_report_id = preflight_report_id
    @destination_captions = destination_captions.to_h.stringify_keys
    @publications = []
    super()
  end

  # Creates one draft for each selected destination that passed the supplied report.
  #
  # @return [Boolean] whether at least one draft was created
  def call
    return false unless step_load_render_version
    return false unless step_load_preflight_report
    return false unless step_load_destinations

    step_create_publications
    step_succeed!
    success?
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  private

  def step_load_render_version
    @render_version = RenderVersion.find_by(id: @render_version_id)
    return true if @render_version

    step_fail!("Không tìm thấy render version cần đăng.")
  end

  def step_load_preflight_report
    @preflight_report = PreflightReport.find_by(id: @preflight_report_id)
    return step_fail!("Không tìm thấy báo cáo preflight.") unless @preflight_report
    return true if @preflight_report.render_version_id == @render_version.id

    step_fail!("Báo cáo preflight không thuộc render version đã chọn.")
  end

  def step_load_destinations
    destination_ids = @destination_captions.keys.map(&:to_i)
    @social_destinations = SocialDestination.where(id: destination_ids).index_by(&:id)
    return step_fail!("Có destination không tồn tại.") unless @social_destinations.size == destination_ids.uniq.size

    checked_ids = @preflight_report.checked_destination_ids.map(&:to_i)
    return true if (destination_ids - checked_ids).empty?

    step_fail!("Báo cáo preflight chưa kiểm tra đủ destination đã chọn.")
  end

  def step_create_publications
    ready_destinations = @social_destinations.values.select do |social_destination|
      @preflight_report.ready_for?(render_version: @render_version, social_destination:)
    end

    return step_fail!("Không có destination nào sẵn sàng để tạo Publication.") if ready_destinations.empty?

    Publication.transaction do
      @publications = ready_destinations.map do |social_destination|
        @render_version.publications.create!(
          social_destination:,
          caption: @destination_captions.fetch(social_destination.id.to_s)
        )
      end
    end
    true
  end
end
