require "rails_helper"

RSpec.describe "Video project pages", type: :request do
  describe "GET /" do
    it "returns the video project list path" do
      get root_path

      expect(response).to redirect_to(video_projects_path)
    end
  end

  describe "GET /video_projects/new" do
    it "returns the new project form" do
      get new_video_project_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /video_projects" do
    it "returns the project list" do
      create(:video_project)

      get video_projects_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /video_projects/:id" do
    it "returns the project workspace" do
      video_project = create(:video_project)

      get video_project_path(video_project)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /video_projects/:id/edit" do
    it "returns the project edit form" do
      video_project = create(:video_project)

      get edit_video_project_path(video_project)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /video_projects" do
    it "returns the created project path after a valid submission" do
      post video_projects_path, params: { video_project: { name: "Summer campaign" } }

      expect(response).to redirect_to(video_project_path(VideoProject.last))
      expect(VideoProject.last.name).to eq("Summer campaign")
    end

    it "returns an unprocessable response when the name is blank" do
      expect do
        post video_projects_path, params: { video_project: { name: " " } }
      end.not_to change(VideoProject, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /video_projects/:id" do
    it "returns the project path after a valid rename" do
      video_project = create(:video_project, name: "Old name")

      patch video_project_path(video_project), params: { video_project: { name: "New name" } }

      expect(response).to redirect_to(video_project_path(video_project))
      expect(video_project.reload.name).to eq("New name")
    end

    it "returns an unprocessable response when the new name is blank" do
      video_project = create(:video_project)

      patch video_project_path(video_project), params: { video_project: { name: " " } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(video_project.reload.name).not_to eq(" ")
    end
  end

  describe "DELETE /video_projects/:id" do
    it "returns the project list path after deleting an empty project" do
      video_project = create(:video_project)

      delete video_project_path(video_project)

      expect(response).to redirect_to(video_projects_path)
      expect(VideoProject.exists?(video_project.id)).to be(false)
    end
  end
end
