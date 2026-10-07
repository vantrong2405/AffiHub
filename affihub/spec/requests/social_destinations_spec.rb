require "rails_helper"

RSpec.describe "Social destination pages", type: :request do
  let(:social_connection) { create(:social_connection) }
  let(:pages) do
    [
      { id: "page-1", name: "Page Một", access_token: "page-token-1", tasks: [ "CREATE_CONTENT" ] },
      { id: "page-2", name: "Page Hai", access_token: "page-token-2", tasks: [ "CREATE_CONTENT" ] }
    ]
  end

  before do
    stub_request(:get, "https://graph.facebook.com/v26.0/me/accounts")
      .with(query: hash_including("access_token" => "user-access-token"))
      .to_return(body: { data: pages }.to_json)
  end

  describe "GET /social_connections/:social_connection_id/social_destinations" do
    it "returns Page choices without Page Access Tokens" do
      get social_connection_social_destinations_path(social_connection)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("page-token-1", "page-token-2")
    end
  end

  describe "POST /social_connections/:social_connection_id/social_destinations" do
    it "returns the Page selections saved from the connected profile" do
      expect do
        post social_connection_social_destinations_path(social_connection), params: {
          social_destination: { external_ids: [ "page-2" ] }
        }
      end.to change(SocialDestination, :count).by(1)

      expect(response).to redirect_to(social_connection_path(social_connection))
      expect(SocialDestination.last.external_id).to eq("page-2")
    end

    context "when a selected Page lacks content permission" do
      let(:pages) do
        [ { id: "page-2", name: "Page Hai", access_token: "page-token-2", tasks: [ "PROFILE_PLUS_ANALYZE" ] } ]
      end

      it "returns to Page selection without persisting the Page" do
        expect do
          post social_connection_social_destinations_path(social_connection), params: {
            social_destination: { external_ids: [ "page-2" ] }
          }
        end.not_to change(SocialDestination, :count)

        expect(response).to redirect_to(social_connection_social_destinations_path(social_connection))
      end
    end
  end
end
