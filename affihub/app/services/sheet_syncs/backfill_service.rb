class SheetSyncs::BackfillService < ApplicationService
  # The explicit SheetSync requests created for the selected render versions.
  # @return [Array<SheetSync>]
  attr_reader :sheet_syncs

  # Initializes a user-selected Sheets backfill for one project.
  #
  # @param google_connection_id [Integer] the configured Sheets connection
  # @param video_project_id [Integer] the project chosen by the user
  # @param render_version_ids [Array<Integer>] the render versions chosen by the user
  # @return [SheetSyncs::BackfillService] the configured service
  def initialize(google_connection_id:, video_project_id:, render_version_ids:)
    @google_connection_id = google_connection_id
    @video_project_id = video_project_id
    @render_version_ids = Array(render_version_ids).map(&:to_i).reject(&:zero?).uniq
    @sheet_syncs = []
    super()
  end

  # Queues only selected renders and their existing publication destinations.
  #
  # @return [Boolean] whether the selected rows were queued
  def call
    return false unless step_load_resources
    return false unless step_validate_selection
    return false unless step_enqueue_selected_rows

    step_succeed!
    success?
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    step_fail!("Không thể lưu các hàng được chọn để đồng bộ.")
  end

  private

  def step_load_resources
    @video_project = VideoProject.find_by(id: @video_project_id)
    @google_connection = GoogleConnection.find_by(id: @google_connection_id)
    return step_fail!("Không tìm thấy Video Project được chọn.") unless @video_project
    return step_fail!("Không tìm thấy kết nối Google Sheets.") unless @google_connection

    true
  end

  def step_validate_selection
    return step_fail!("Kết nối đã chọn không phải Google Sheets.") unless @google_connection.integration == "sheets"
    return step_fail!("Google Sheets cần kết nối lại trước khi đồng bộ.") unless @google_connection.connected?
    return step_fail!("Hãy chọn spreadsheet và tab trước khi đồng bộ.") if
      @google_connection.spreadsheet_id.blank? || @google_connection.worksheet_title.blank?
    return step_fail!("Chọn ít nhất một bản render để đồng bộ.") if @render_version_ids.empty?

    @render_versions = @video_project.render_versions.where(id: @render_version_ids).to_a
    return step_fail!("Có bản render không thuộc Video Project đã chọn.") unless
      @render_versions.map(&:id).sort == @render_version_ids.sort

    true
  end

  def step_enqueue_selected_rows
    @render_versions.each do |render_version|
      destination_ids = Publication.where(render_version_id: render_version.id)
        .distinct.pluck(:social_destination_id)
      destination_ids.each do |social_destination_id|
        service = SheetSyncs::CreateService.new(
          google_connection_id: @google_connection.id,
          render_version_id: render_version.id,
          social_destination_id:
        )
        return step_fail!(service.errors.full_messages.to_sentence) unless service.call

        sheet_syncs << service.sheet_sync
      end
    end
    return step_fail!("Các bản render đã chọn chưa có destination Publication để đồng bộ.") if sheet_syncs.empty?

    true
  end
end
