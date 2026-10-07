require "rails_helper"

RSpec.describe "SocialDestinations::CreateService", type: :service do
  describe "#call" do
    it "returns only the Page explicitly selected from the connected profile" do
      social_connection = create(:social_connection)
      stub_request(:get, %r{graph.facebook.com/v26.0/me/accounts})
        .to_return(body: { data: [
          { id: "page-1", name: "Page Một", access_token: "page-token-1", tasks: [ "CREATE_CONTENT" ] },
          { id: "page-2", name: "Page Hai", access_token: "page-token-2", tasks: [ "CREATE_CONTENT" ] }
        ] }.to_json)
      service = "SocialDestinations::CreateService".constantize.new(
        social_connection_id: social_connection.id, external_id: "page-2"
      )

      service.call

      expect(service).to be_success
      expect(service.social_destination.external_id).to eq("page-2")
      expect(service.social_destination.name).to eq("Page Hai")
    end
  end
end
