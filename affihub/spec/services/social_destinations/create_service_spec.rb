require "rails_helper"

RSpec.describe "SocialDestinations::CreateService", type: :service do
  describe "#call" do
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

    it "returns only the Page explicitly selected by the connected profile" do
      service = SocialDestinations::CreateService.new(
        social_connection_id: social_connection.id, external_ids: [ "page-2" ]
      )

      service.call

      expect(service.social_destinations.map(&:external_id)).to eq([ "page-2" ])
    end

    it "returns every authorized Page explicitly selected by the connected profile" do
      service = SocialDestinations::CreateService.new(
        social_connection_id: social_connection.id, external_ids: [ "page-1", "page-2" ]
      )

      expect { service.call }.to change(SocialDestination, :count).by(2)
    end

    it "returns a selection error when no Page is selected" do
      service = SocialDestinations::CreateService.new(
        social_connection_id: social_connection.id, external_ids: []
      )

      expect { service.call }.not_to change(SocialDestination, :count)
      expect(service.errors.full_messages.to_sentence).to eq("Chọn ít nhất một Page.")
    end

    it "returns an ownership error when a selected Page is not in the profile list" do
      service = SocialDestinations::CreateService.new(
        social_connection_id: social_connection.id, external_ids: [ "page-outside-profile" ]
      )

      expect { service.call }.not_to change(SocialDestination, :count)
      expect(service.errors.full_messages.to_sentence).to eq("Một hoặc nhiều Page không thuộc profile Facebook đang kết nối.")
    end

    context "when Meta returns the new Page content task" do
      let(:pages) do
        [ { id: "page-3", name: "Page Ba", access_token: "page-token-3", tasks: [ "PROFILE_PLUS_CREATE_CONTENT" ] } ]
      end

      it "returns the Page selected with its authorized content task" do
        service = SocialDestinations::CreateService.new(
          social_connection_id: social_connection.id, external_ids: [ "page-3" ]
        )

        service.call

        expect(service.social_destinations.first.external_id).to eq("page-3")
      end
    end

    context "when one selected Page lacks the content task" do
      let(:pages) do
        [
          { id: "page-1", name: "Page Một", access_token: "page-token-1", tasks: [ "CREATE_CONTENT" ] },
          { id: "page-2", name: "Page Hai", access_token: "page-token-2", tasks: [ "PROFILE_PLUS_ANALYZE" ] }
        ]
      end

      it "returns a permission error without saving any selected Page" do
        service = SocialDestinations::CreateService.new(
          social_connection_id: social_connection.id, external_ids: [ "page-1", "page-2" ]
        )

        expect { service.call }.not_to change(SocialDestination, :count)
        expect(service).not_to be_success
      end
    end

    context "when Meta does not return a Page Access Token" do
      let(:pages) do
        [ { id: "page-1", name: "Page Một", tasks: [ "CREATE_CONTENT" ] } ]
      end

      it "returns a token error without saving the selected Page" do
        service = SocialDestinations::CreateService.new(
          social_connection_id: social_connection.id, external_ids: [ "page-1" ]
        )

        expect { service.call }.not_to change(SocialDestination, :count)
        expect(service.errors.full_messages.to_sentence).to eq("Meta không trả Page Access Token cho Page đã chọn.")
      end
    end
  end
end
