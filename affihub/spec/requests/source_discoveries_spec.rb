require "rails_helper"

RSpec.describe "Source discoveries", type: :request do
  describe "GET /video_projects/:video_project_id/source_discoveries/new" do
    it "returns the YouTube discovery form" do
      video_project = create(:video_project)

      get new_video_project_source_discovery_path(video_project)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /video_projects/:video_project_id/source_discoveries" do
    it "persists keyword results and redirects to the project-scoped results page" do
      video_project = create(:video_project)
      stub_request(:get, "https://www.googleapis.com/youtube/v3/search")
        .with(query: hash_including("q" => "quay video dep"))
        .to_return(
          body: {
            items: [
              {
                id: { videoId: "video-123" },
                snippet: {
                  title: "Quay video đẹp bằng điện thoại",
                  channelTitle: "Minh An",
                  thumbnails: { high: { url: "https://i.ytimg.com/vi/video-123/hqdefault.jpg" } }
                }
              }
            ]
          }.to_json
        )

      expect do
        post video_project_source_discoveries_path(video_project),
             params: { source_discovery: { search_type: "keyword", search_query: "quay video dep" } }
      end.to change(SourceDiscovery, :count).by(1)
        .and change(YoutubeDiscoveryMetadata, :count).by(1)
        .and change(SourceDiscoveryResult, :count).by(1)

      discovery = SourceDiscovery.last
      expect(response).to redirect_to(video_project_source_discovery_path(video_project, discovery))
      expect(discovery).to have_attributes(search_type: "keyword", search_query: "quay video dep", region_code: "VN")
      expect(discovery.source_discovery_results.sole.youtube_discovery_metadata)
        .to have_attributes(title: "Quay video đẹp bằng điện thoại", channel_title: "Minh An")
    end

    it "persists regional popular results with the selected category" do
      video_project = create(:video_project)
      stub_request(:get, "https://www.googleapis.com/youtube/v3/videos")
        .with(query: hash_including(
          "chart" => "mostPopular",
          "regionCode" => "VN",
          "videoCategoryId" => "10"
        ))
        .to_return(body: { items: [] }.to_json)

      expect do
        post video_project_source_discoveries_path(video_project),
             params: {
               source_discovery: {
                 search_type: "regional_popular",
                 region_code: "VN",
                 video_category_id: "10"
               }
             }
      end.to change(SourceDiscovery, :count).by(1)

      expect(SourceDiscovery.last).to have_attributes(
        search_type: "regional_popular",
        region_code: "VN",
        video_category_id: "10"
      )
      expect(response).to redirect_to(video_project_source_discovery_path(video_project, SourceDiscovery.last))
    end

    it "returns a safe error when YouTube quota is exhausted without persisting results" do
      video_project = create(:video_project)
      stub_request(:get, "https://www.googleapis.com/youtube/v3/search")
        .with(query: hash_including("q" => "quay video"))
        .to_return(
          status: 403,
          body: { error: { errors: [ { reason: "quotaExceeded" } ] } }.to_json
        )

      expect do
        post video_project_source_discoveries_path(video_project),
             params: { source_discovery: { search_type: "keyword", search_query: "quay video" } }
      end.not_to change(SourceDiscovery, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(YoutubeDiscoveryMetadata.count).to eq(0)
    end
  end

  describe "GET /video_projects/:video_project_id/source_discoveries/:id" do
    it "returns the persisted result set for its project" do
      video_project = create(:video_project)
      discovery = create(:source_discovery, video_project:)
      metadata = create(:youtube_discovery_metadata)
      create(:source_discovery_result, source_discovery: discovery, youtube_discovery_metadata: metadata)

      get video_project_source_discovery_path(video_project, discovery)

      expect(response).to have_http_status(:ok)
    end

    it "does not show a discovery owned by another project" do
      video_project = create(:video_project)
      discovery = create(:source_discovery)

      get video_project_source_discovery_path(video_project, discovery)

      expect(response).to have_http_status(:not_found)
    end
  end
end
