require "rails_helper"

RSpec.describe SocialDestinations::CreateService, type: :service do
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
        .with(query: { "fields" => "id,name,access_token,tasks", "access_token" => "user-access-token" })
        .to_return(body: { data: pages }.to_json)
    end

    it "returns only the Page explicitly selected by the connected profile" do
      service = described_class.new(
        social_connection_id: social_connection.id, external_ids: [ "page-2" ]
      )

      service.call

      expect(service.social_destinations.map(&:external_id)).to eq([ "page-2" ])
    end

    it "returns every authorized Page explicitly selected by the connected profile" do
      service = described_class.new(
        social_connection_id: social_connection.id, external_ids: [ "page-1", "page-2" ]
      )

      expect { service.call }.to change(SocialDestination, :count).by(2)
    end

    it "returns a selection error when no Page is selected" do
      service = described_class.new(
        social_connection_id: social_connection.id, external_ids: []
      )

      expect { service.call }.not_to change(SocialDestination, :count)
      expect(service.errors.full_messages.to_sentence).to eq("Chọn ít nhất một Page.")
    end

    it "returns an ownership error when a selected Page is not in the profile list" do
      service = described_class.new(
        social_connection_id: social_connection.id, external_ids: [ "page-outside-profile" ]
      )

      expect { service.call }.not_to change(SocialDestination, :count)
      expect(service.errors.full_messages.to_sentence).to eq("Một hoặc nhiều Page không thuộc profile đang kết nối.")
    end

    context "when Meta returns the new Page content task" do
      let(:pages) do
        [ { id: "page-3", name: "Page Ba", access_token: "page-token-3", tasks: [ "PROFILE_PLUS_CREATE_CONTENT" ] } ]
      end

      it "returns the Page selected with its authorized content task" do
        service = described_class.new(
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
        service = described_class.new(
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
        service = described_class.new(
          social_connection_id: social_connection.id, external_ids: [ "page-1" ]
        )

        expect { service.call }.not_to change(SocialDestination, :count)
        expect(service.errors.full_messages.to_sentence).to eq("Meta không trả Page Access Token cho Page đã chọn.")
      end
    end

    context "when selecting a Page for Instagram" do
      let(:social_connection) { create(:social_connection, provider: "instagram") }
      let(:pages) do
        [
          {
            id: "page-1",
            name: "Page Một",
            access_token: "instagram-page-token-secret",
            tasks: [ "CREATE_CONTENT" ],
            instagram_business_account: { id: "ig-business-1", account_type: "BUSINESS" }
          }
        ]
      end

      before do
        stub_request(:get, "https://graph.facebook.com/v26.0/me/accounts")
          .with(query: {
            "fields" => "id,name,access_token,tasks,instagram_business_account{id,account_type}",
            "access_token" => "user-access-token"
          })
          .to_return(body: { data: pages }.to_json)
      end

      it "returns an Instagram destination with the selected Page and Business account mapping" do
        service = described_class.new(social_connection_id: social_connection.id, external_ids: [ "page-1" ])

        expect(service.call).to eq(true)

        social_destination = service.social_destinations.sole
        expect(social_destination.provider).to eq("instagram")
        expect(social_destination.external_id).to eq("ig-business-1")
        expect(social_destination.access_token).to eq("instagram-page-token-secret")
        expect(social_destination.metadata).to eq(
          "page_id" => "page-1",
          "instagram_business_account_id" => "ig-business-1",
          "instagram_account_type" => "BUSINESS",
          "tasks" => [ "CREATE_CONTENT" ]
        )
        expect(social_destination.read_attribute_before_type_cast(:access_token)).not_to match("instagram-page-token-secret")
      end

      context "when the selected Page has no linked Instagram account" do
        let(:pages) do
          [ { id: "page-1", name: "Page Một", access_token: "page-token", tasks: [ "CREATE_CONTENT" ] } ]
        end

        it "returns false without creating an Instagram destination" do
          service = described_class.new(social_connection_id: social_connection.id, external_ids: [ "page-1" ])

          expect(service.call).to eq(false)
          expect(SocialDestination.where(social_connection:).count).to eq(0)
          expect(service.errors.full_messages.to_sentence).to eq("Page chưa liên kết Instagram Business account.")
        end
      end

      context "when the selected Page links an Instagram Creator account" do
        let(:pages) do
          [
            {
              id: "page-creator",
              name: "Page Creator",
              access_token: "page-token",
              tasks: [ "CREATE_CONTENT" ],
              instagram_business_account: { id: "ig-creator-1", account_type: "CREATOR" }
            }
          ]
        end

        it "returns false without creating an Instagram destination" do
          service = described_class.new(social_connection_id: social_connection.id, external_ids: [ "page-creator" ])

          expect(service.call).to eq(false)
          expect(SocialDestination.where(social_connection:).count).to eq(0)
          expect(service.errors.full_messages.to_sentence).to eq("MVP chỉ hỗ trợ tài khoản Instagram Business có Page liên kết.")
        end
      end
    end

    context "when selecting a YouTube channel" do
      let(:social_connection) do
        create(:social_connection, provider: "youtube", external_user_id: "google-sub-1")
      end

      before do
        stub_request(:get, "https://www.googleapis.com/youtube/v3/channels")
          .with(query: { "part" => "snippet", "mine" => "true", "maxResults" => "50" })
          .with(headers: { "Authorization" => "Bearer user-access-token" })
          .to_return(body: { items: [
            { id: "channel-1", snippet: { title: "Kênh Một" } },
            { id: "channel-2", snippet: { title: "Kênh Hai" } }
          ] }.to_json)
      end

      it "returns only the selected channel as an encrypted YouTube destination" do
        service = described_class.new(social_connection_id: social_connection.id, external_ids: [ "channel-2" ])

        expect(service.call).to eq(true)

        destination = service.social_destinations.sole
        expect(destination.provider).to eq("youtube")
        expect(destination.external_id).to eq("channel-2")
        expect(destination.name).to eq("Kênh Hai")
        expect(destination.access_token).to eq("user-access-token")
        expect(destination.read_attribute_before_type_cast(:access_token)).not_to match("user-access-token")
        expect(social_connection.social_destinations.pluck(:external_id)).to eq([ "channel-2" ])
      end

      it "returns false when the selected channel is not owned by the connected account" do
        service = described_class.new(social_connection_id: social_connection.id, external_ids: [ "other-channel" ])

        expect(service.call).to eq(false)
        expect(social_connection.social_destinations.count).to eq(0)
      end
    end
  end
end
