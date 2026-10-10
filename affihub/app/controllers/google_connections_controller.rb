class GoogleConnectionsController < MainController
  # Lists saved optional Google integrations and connection choices.
  #
  # @return [ActionController::Metal::Response] the integration index response
  def index
    service = GoogleConnections::IndexService.new
    service.call
    return render_service(service, failure_redirect: root_path) unless service.success?

    @google_connections = service.google_connections
    @has_google_connections = service.has_google_connections
    @oauth_configured = service.oauth_configured
  end

  # Prepares the consent screen for one supported Google integration.
  #
  # @return [ActionController::Metal::Response] the integration selection response
  def new
    service = GoogleConnections::NewService.new(integration: params[:integration])
    service.call
    return render_service(service, failure_redirect: google_connections_path) unless service.success?

    @integration = service.integration
    @oauth_configured = service.oauth_configured
  end

  # Starts OAuth for the selected Google integration.
  #
  # @return [ActionController::Metal::Response] the authorization redirect response
  def create
    service = GoogleConnections::CreateService.new(integration: params[:integration], session:)
    service.call
    render_service(service, failure_redirect: google_connections_path, allow_other_host: true) do
      service.authorization_url
    end
  end

  # Shows the saved account and its available Drive folder or Sheets tab options.
  #
  # @return [ActionController::Metal::Response] the integration settings response
  def show
    service = google_connection_show_service
    service.call
    return render_service(service, failure_redirect: google_connections_path) unless service.success?

    assign_google_connection_settings(service)
  end

  # Opens the existing connection form through its standard edit route.
  #
  # @return [ActionController::Metal::Response] the connection settings response
  def edit
    service = google_connection_show_service
    service.call
    return render_service(service, failure_redirect: google_connections_path) unless service.success?

    assign_google_connection_settings(service)
    render :show
  end

  # Saves the selected Drive folder or spreadsheet tab.
  #
  # @return [ActionController::Metal::Response] the settings update response
  def update
    service = GoogleConnections::UpdateService.new(
      google_connection_id: params[:id],
      attributes: google_connection_params
    )
    service.call

    render_service(
      service,
      success: google_connection_path(params[:id]),
      failure_redirect: google_connection_path(params[:id]),
      notice: "Đã lưu cấu hình đồng bộ Google."
    )
  end

  private

  def google_connection_show_service
    GoogleConnections::ShowService.new(
      google_connection_id: params[:id],
      spreadsheet_id: params[:spreadsheet_id],
      worksheet_title: params[:worksheet_title]
    )
  end

  def assign_google_connection_settings(service)
    @google_connection = service.google_connection
    @drive_folders = service.drive_folders
    @worksheets = service.worksheets
    @spreadsheet_id = service.spreadsheet_id
    @picker_configuration = service.picker_configuration
    @picker_ready = service.picker_ready
    @worksheet_title = service.worksheet_title
    @option_load_error = service.option_load_error
    @has_option_load_error = service.has_option_load_error
    @drive_integration = service.drive_integration
    @connection_connected = service.connection_connected
    @has_worksheets = service.has_worksheets
  end

  def google_connection_params
    params.require(:google_connection).permit(:drive_parent_folder_id, :spreadsheet_id, :worksheet_title)
  end
end
