require "rails_helper"

RSpec.describe "Local render exports", type: :request do
  describe "GET Active Storage blob" do
    it "returns the MP4 bytes without starting a publish job" do
      render_version = create(:render_version, status: "ready")
      render_version.file.attach(
        io: StringIO.new("rendered MP4 bytes"),
        filename: "rendered-video.mp4",
        content_type: "video/mp4"
      )
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      get rails_blob_path(render_version.file, disposition: "attachment")
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("rendered MP4 bytes")
      expect(response.headers.fetch("Content-Disposition").split(";").first).to eq("attachment")
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to eq([])
    end
  end
end
