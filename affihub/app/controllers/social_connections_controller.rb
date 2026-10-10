class SocialConnectionsController < MainController
  # Lists social profiles connected to this AffiHub installation.
  #
  # @return [ActionController::Metal::Response] the profile list response
  def index
    service = SocialConnections::IndexService.new
    service.call
    @social_connections = service.social_connections
  end

  # Shows setup availability for the selected provider.
  #
  # @return [ActionController::Metal::Response] the provider setup response
  def new
    service = SocialConnections::NewService.new(provider: params[:provider])
    service.call
    return render_service(service, failure_redirect: social_connections_path) unless service.success?

    @provider = service.provider
    @provider_configured = service.provider_configured
  end

  # Shows a connected profile and its publishing destinations.
  #
  # @return [ActionController::Metal::Response] the profile detail response
  def show
    service = SocialConnections::ShowService.new(social_connection_id: params[:id])
    service.call
    return render_service(service, failure_redirect: social_connections_path) unless service.success?

    @social_connection = service.social_connection
    @social_destinations = service.social_destinations
  end

  # Starts OAuth for a provider and redirects to its authorization page.
  def create
    service = SocialConnections::CreateService.new(provider: params[:provider], session:)
    service.call
    render_service(service, failure: :new, allow_other_host: true) do
      service.authorization_url
    end
  end
end
