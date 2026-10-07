require "rails_helper"

RSpec.describe "SocialDestinations::IndexService", type: :service do
  describe "#call" do
    it "returns Page choices and permission status without Page Access Tokens" do
      social_connection = create(:social_connection)
      stub_request(:get, "https://graph.facebook.com/v26.0/me/accounts")
        .with(query: hash_including("access_token" => "user-access-token"))
        .to_return(body: { data: [
          { id: "page-1", name: "Page Có quyền", access_token: "page-token-secret", tasks: [ "PROFILE_PLUS_CREATE_CONTENT" ] },
          { id: "page-2", name: "Page Chỉ xem", access_token: "other-page-token", tasks: [ "PROFILE_PLUS_ANALYZE" ] }
        ] }.to_json)
      service = SocialDestinations::IndexService.new(social_connection_id: social_connection.id)

      service.call

      expect(service.available_pages).to eq([
        { "id" => "page-1", "name" => "Page Có quyền", "tasks" => [ "PROFILE_PLUS_CREATE_CONTENT" ], "can_create_content" => true },
        { "id" => "page-2", "name" => "Page Chỉ xem", "tasks" => [ "PROFILE_PLUS_ANALYZE" ], "can_create_content" => false }
      ])
    end

    it "returns a safe error when Meta cannot list Pages" do
      social_connection = create(:social_connection)
      stub_request(:get, "https://graph.facebook.com/v26.0/me/accounts")
        .with(query: hash_including("access_token" => "user-access-token"))
        .to_return(status: 403, body: { error: { message: "page-token-secret denied" } }.to_json)
      service = SocialDestinations::IndexService.new(social_connection_id: social_connection.id)

      service.call

      expect(service.available_pages).to eq([])
      expect(service.errors.full_messages.to_sentence).to eq("Không thể đọc danh sách Page từ Meta.")
    end
  end
end
