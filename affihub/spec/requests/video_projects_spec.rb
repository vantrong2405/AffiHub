# frozen_string_literal: true

require "rails_helper"
require "tempfile"

RSpec.describe "Local video workflow", type: :request do
  let(:video_bytes) { "local video bytes" }
  let(:temporary_file) { Tempfile.new(["local-video", ".mp4"]) }
  let(:uploaded_file) do
    temporary_file.binmode
    temporary_file.write(video_bytes)
    temporary_file.rewind
    Rack::Test::UploadedFile.new(temporary_file.path, "video/mp4")
  end

  after do
    temporary_file.close!
  end

  it "imports and exports a local render without credentials or social requests" do
    expect do
      post "/videos", params: { file: uploaded_file }
    end.to change(VideoProject, :count).by(1)
      .and change(SourceAsset, :count).by(1)
      .and change(RenderVersion, :count).by(1)

    video_project = VideoProject.order(:id).last
    render_version = video_project.render_versions.sole

    expect(response).to redirect_to("/videos/#{video_project.id}")

    get response.location

    expect(response).to have_http_status(:ok)

    get "/render_versions/#{render_version.id}/export"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("video/mp4")
    expect(response.body).to eq(video_bytes)
    expect(render_version.metadata).to eq({})
    expect(a_request(:any, %r{\Ahttps://[^/]*(?:facebook|tiktok|instagram|youtube)[^/]*/})).not_to have_been_made
  end

  it "rejects unsupported video types without creating a project" do
    temporary_file.binmode
    temporary_file.write(video_bytes)
    temporary_file.rewind
    uploaded_file = Rack::Test::UploadedFile.new(temporary_file.path, "video/webm")

    expect do
      post "/videos", params: { file: uploaded_file }
    end.not_to change(VideoProject, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end
end
