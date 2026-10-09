class SheetSyncs::ShowService < ApplicationService
  # The project that owns the selected SheetSync render.
  # @return [VideoProject, nil]
  attr_reader :video_project

  # The selected project-scoped SheetSync record.
  # @return [SheetSync, nil]
  attr_reader :sheet_sync

  # The latest local Publication row represented by this sync.
  # @return [Publication, nil]
  attr_reader :publication

  # Reports whether an idempotent Sheets upsert can be queued again.
  # @return [Boolean]
  attr_reader :can_retry

  # Reports whether the sync row has a safe error code to show.
  # @return [Boolean]
  attr_reader :has_safe_error

  # Reports whether the row currently has a local Publication history record.
  # @return [Boolean]
  attr_reader :has_publication

  # The safe machine code for a Google Sheets sync error.
  # @return [String, nil]
  attr_reader :safe_error_code

  # Reports whether the current sync result is ambiguous after a timeout.
  # @return [Boolean]
  attr_reader :outcome_unknown

  # Reports whether the local Publication has a safe platform error code.
  # @return [Boolean]
  attr_reader :has_publication_error

  # Initializes one project-scoped Sheets status page.
  #
  # @param video_project_id [Integer] the owning project
  # @param sheet_sync_id [Integer] the selected sync row
  # @return [SheetSyncs::ShowService] the configured service
  def initialize(video_project_id:, sheet_sync_id:)
    @video_project_id = video_project_id
    @sheet_sync_id = sheet_sync_id
    super()
  end

  # Loads the selected sync row and its latest local Publication state.
  #
  # @return [Boolean] whether the row was found
  def call
    return false unless step_load_project
    return false unless step_load_sheet_sync

    @publication = Publication.where(
      render_version_id: sheet_sync.render_version_id,
      social_destination_id: sheet_sync.social_destination_id
    ).order(created_at: :desc, id: :desc).first
    @has_publication = publication.present?
    @safe_error_code = sheet_sync.safe_error_code
    @has_safe_error = safe_error_code.present?
    @outcome_unknown = sheet_sync.outcome_unknown?
    @has_publication_error = publication&.safe_error_code.present?
    @can_retry = !sheet_sync.succeeded? && !sheet_sync.queued? && !sheet_sync.syncing?
    step_succeed!
    success?
  end

  private

  def step_load_project
    @video_project = VideoProject.find_by(id: @video_project_id)
    return true if video_project

    step_fail!("Không tìm thấy project video.")
  end

  def step_load_sheet_sync
    @sheet_sync = SheetSync.joins(:render_version)
      .includes(:google_connection, :social_destination, render_version: :video_project)
      .find_by(id: @sheet_sync_id, render_versions: { video_project_id: video_project.id })
    return true if sheet_sync

    step_fail!("Không tìm thấy hàng đồng bộ Sheets trong project này.")
  end
end
