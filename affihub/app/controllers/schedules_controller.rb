class SchedulesController < MainController
  # Lists the schedules belonging to one video project.
  #
  # @return [ActionController::Metal::Response] the project schedule list
  def index
    service = Schedules::IndexService.new(video_project_id: params[:video_project_id])
    service.call
    @video_project = service.video_project
    @schedules = service.schedules
  end

  # Loads a schedule and its occurrence and quota history.
  #
  # @return [ActionController::Metal::Response] the Schedule detail response
  def show
    load_schedule_detail
  end

  # Loads preflight-ready destinations and the local timezone default.
  #
  # @return [ActionController::Metal::Response] the new Schedule response
  def new
    @schedule_form = Schedules::CreateForm.new(preflight_report_id: params[:preflight_report_id])
    load_new_form
  end

  # Creates a Schedule from the selected report and saved destination consent.
  #
  # @return [ActionController::Metal::Response] the Schedule create response
  def create
    @schedule_form = Schedules::CreateForm.new(schedule_params)
    form_service = load_new_form(@schedule_form.preflight_report_id)
    unless form_service.success?
      flash.now[:alert] = form_service.errors.full_messages.to_sentence
      return render(:new, status: :unprocessable_content)
    end

    service = Schedules::CreateService.new(
      video_project_id: params[:video_project_id],
      render_version_id: @schedule_form.render_version_id,
      preflight_report_id: @schedule_form.preflight_report_id,
      scheduled_at: @schedule_form.scheduled_at,
      time_zone: @schedule_form.time_zone,
      recurrence: @schedule_form.recurrence,
      destination_settings: @schedule_form.destination_settings(form_service.publications_by_destination)
    )
    service.call
    @schedule = service.schedule

    render_service(service, failure: :new, notice: "Đã tạo lịch đăng.") do
      video_project_schedule_path(params[:video_project_id], service.schedule)
    end
  end

  # Loads a Schedule into its editable form.
  #
  # @return [ActionController::Metal::Response] the edit Schedule response
  def edit
    load_schedule_detail
    @schedule_form = Schedules::CreateForm.new
  end

  # Updates Schedule timing, timezone, recurrence, or pause state.
  #
  # @return [ActionController::Metal::Response] the Schedule update response
  def update
    permitted_params = schedule_params
    @schedule_form = Schedules::CreateForm.new(permitted_params)
    service = Schedules::UpdateService.new(
      video_project_id: params[:video_project_id],
      schedule_id: params[:id],
      status: permitted_params[:status],
      scheduled_at: @schedule_form.scheduled_at,
      time_zone: @schedule_form.time_zone,
      recurrence: @schedule_form.recurrence
    )
    service.call
    load_schedule_detail

    render_service(service, failure: :edit, notice: "Đã cập nhật lịch đăng.") do
      video_project_schedule_path(@video_project, service.schedule)
    end
  end

  # Cancels a Schedule and skips occurrences not yet dispatched.
  #
  # @return [ActionController::Metal::Response] the Schedule cancellation response
  def destroy
    service = Schedules::UpdateService.new(
      video_project_id: params[:video_project_id],
      schedule_id: params[:id],
      status: "cancelled"
    )
    service.call

    render_service(
      service,
      success: video_project_schedules_path(params[:video_project_id]),
      failure_redirect: video_project_schedule_path(params[:video_project_id], params[:id]),
      notice: "Đã hủy lịch đăng."
    )
  end

  private

  def load_new_form(preflight_report_id = params[:preflight_report_id])
    service = Schedules::NewService.new(
      video_project_id: params[:video_project_id],
      preflight_report_id:
    )
    service.call
    @video_project = service.video_project
    @preflight_reports = service.preflight_reports
    @preflight_report = service.preflight_report
    @render_version = service.render_version
    @ready_social_destinations = service.ready_social_destinations
    @blocked_social_destinations = service.blocked_social_destinations
    @time_zone = service.time_zone
    @time_zone_options = service.time_zone_options
    @publications_by_destination = service.publications_by_destination
    @consent_required_destination_ids = service.consent_required_destination_ids
    service
  end

  def load_schedule_detail
    service = Schedules::ShowService.new(
      video_project_id: params[:video_project_id],
      schedule_id: params[:id]
    )
    service.call
    @video_project = service.video_project
    @schedule = service.schedule
    @occurrences = service.occurrences
    @quota_summary = service.quota_summary
  end

  def schedule_params
    params.require(:schedule).permit(
      :render_version_id,
      :preflight_report_id,
      :scheduled_at,
      :time_zone,
      :recurrence,
      :status,
      destination_ids: [],
      destination_captions: {}
    )
  end
end
