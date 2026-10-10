require "rails_helper"

RSpec.describe SocialDestinations::IndexService, type: :service do
  describe "#call" do
    it "returns Page choices and permission status without Page Access Tokens" do
      social_connection = create(:social_connection)
      stub_request(:get, "https://graph.facebook.com/v26.0/me/accounts")
        .with(query: { "fields" => "id,name,access_token,tasks", "access_token" => "user-access-token" })
        .to_return(body: { data: [
          { id: "page-1", name: "Page Có quyền", access_token: "page-token-secret", tasks: [ "PROFILE_PLUS_CREATE_CONTENT" ] },
          { id: "page-2", name: "Page Chỉ xem", access_token: "other-page-token", tasks: [ "PROFILE_PLUS_ANALYZE" ] }
        ] }.to_json)
      service = described_class.new(social_connection_id: social_connection.id)

      service.call

      expect(service.available_pages).to eq([
        { "id" => "page-1", "name" => "Page Có quyền", "tasks" => [ "PROFILE_PLUS_CREATE_CONTENT" ], "can_create_content" => true },
        { "id" => "page-2", "name" => "Page Chỉ xem", "tasks" => [ "PROFILE_PLUS_ANALYZE" ], "can_create_content" => false }
      ])
    end

    it "returns a safe error when Meta cannot list Pages" do
      social_connection = create(:social_connection)
      stub_request(:get, "https://graph.facebook.com/v26.0/me/accounts")
        .with(query: { "fields" => "id,name,access_token,tasks", "access_token" => "user-access-token" })
        .to_return(status: 403, body: { error: { message: "page-token-secret denied" } }.to_json)
      service = described_class.new(social_connection_id: social_connection.id)

      service.call

      expect(service.available_pages).to eq([])
      expect(service.errors.full_messages.to_sentence).to eq("Không thể đọc danh sách Page từ Meta.")
    end

    context "when the connection uses Instagram Facebook Login" do
      it "returns Page choices with Instagram account IDs and without Page tokens" do
        social_connection = create(:social_connection, provider: "instagram")
        stub_request(:get, "https://graph.facebook.com/v26.0/me/accounts")
          .with(query: {
            "fields" => "id,name,access_token,tasks,instagram_business_account{id,account_type}",
            "access_token" => "user-access-token"
          })
          .to_return(body: { data: [
            {
              id: "page-1",
              name: "Page Có Instagram",
              access_token: "page-token-secret",
              tasks: [ "CREATE_CONTENT" ],
              instagram_business_account: { id: "ig-business-1", account_type: "BUSINESS" }
            },
            {
              id: "page-2",
              name: "Page Chưa liên kết",
              access_token: "other-page-token",
              tasks: [ "CREATE_CONTENT" ]
            }
          ] }.to_json)
        service = described_class.new(social_connection_id: social_connection.id)

        expect(service.call).to eq(true)
        expect(service.available_pages).to eq([
          {
            "id" => "page-1",
            "name" => "Page Có Instagram",
            "tasks" => [ "CREATE_CONTENT" ],
            "can_create_content" => true,
            "instagram_business_account_id" => "ig-business-1",
            "instagram_account_type" => "BUSINESS",
            "instagram_account_eligible" => true
          },
          {
            "id" => "page-2",
            "name" => "Page Chưa liên kết",
            "tasks" => [ "CREATE_CONTENT" ],
            "can_create_content" => true,
            "instagram_business_account_id" => nil,
            "instagram_account_type" => nil,
            "instagram_account_eligible" => false
          }
        ])
      end

      it "returns the linked Creator account type so the product eligibility gate can explain the restriction" do
        social_connection = create(:social_connection, provider: "instagram")
        stub_request(:get, "https://graph.facebook.com/v26.0/me/accounts")
          .with(query: {
            "fields" => "id,name,access_token,tasks,instagram_business_account{id,account_type}",
            "access_token" => "user-access-token"
          })
          .to_return(body: { data: [
            {
              id: "page-creator",
              name: "Page Creator",
              access_token: "page-token-secret",
              tasks: [ "CREATE_CONTENT" ],
              instagram_business_account: { id: "ig-creator-1", account_type: "CREATOR" }
            }
          ] }.to_json)
        service = described_class.new(social_connection_id: social_connection.id)

        expect(service.call).to eq(true)
        expect(service.available_pages).to eq([
          {
            "id" => "page-creator",
            "name" => "Page Creator",
            "tasks" => [ "CREATE_CONTENT" ],
            "can_create_content" => true,
            "instagram_business_account_id" => "ig-creator-1",
            "instagram_account_type" => "CREATOR",
            "instagram_account_eligible" => false
          }
        ])
      end
    end

    context "when the connection uses YouTube" do
      it "returns the user's channel choices without choosing a channel automatically" do
        social_connection = create(:social_connection, provider: "youtube", external_user_id: "google-sub-1")
        stub_request(:get, "https://www.googleapis.com/youtube/v3/channels")
          .with(query: { "part" => "snippet", "mine" => "true", "maxResults" => "50" })
          .with(headers: { "Authorization" => "Bearer user-access-token" })
          .to_return(body: { items: [
            { id: "channel-1", snippet: { title: "Kênh Một" } },
            { id: "channel-2", snippet: { title: "Kênh Hai" } }
          ] }.to_json)
        service = described_class.new(social_connection_id: social_connection.id)

        expect(service.call).to eq(true)
        expect(service.available_destinations).to eq([
          { "id" => "channel-1", "name" => "Kênh Một" },
          { "id" => "channel-2", "name" => "Kênh Hai" }
        ])
        expect(social_connection.social_destinations.count).to eq(0)
      end
    end
  end
end
