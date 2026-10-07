class SocialConnectionsController < MainController
  # Starts OAuth for a provider and redirects to its authorization page.
  def create
    service = SocialConnections::CreateService.new(provider: params[:provider], session:)
    service.call
    render_service(service, failure: :new, allow_other_host: true) do
      service.authorization_url
    end
  end
end
