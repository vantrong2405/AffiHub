# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mpt::Client, type: :service do
  let(:client) { described_class.new }

  describe "#generate_script" do
    let(:script_inputs) do
      {
        video_subject: "Summer skincare",
        video_language: "vi",
        paragraph_number: 1,
        video_script_prompt: "Write a friendly 30-second script.",
        custom_system_prompt: ""
      }
    end
    let(:script_request) do
      stub_request(:post, "http://mpt.test/api/v1/scripts")
        .with(
          headers: { "x-api-key" => "affihub-test-key" },
          body: {
            "video_subject" => "Summer skincare",
            "video_language" => "vi",
            "paragraph_number" => 1,
            "video_script_prompt" => "Write a friendly 30-second script.",
            "custom_system_prompt" => ""
          }
        )
        .to_return(status: 200, body: { status: 200, data: { video_script: "A summer story." } }.to_json)
    end
    subject(:script) { client.generate_script(**script_inputs) }

    before { script_request }

    it "returns the script from the authenticated MPT response" do
      expect(script).to eq("video_script" => "A summer story.")
      expect(script_request).to have_been_requested.once
    end

    context "when MPT responds with an HTTP error" do
      let(:script_request) do
        stub_request(:post, "http://mpt.test/api/v1/scripts")
          .to_return(status: 500, body: "affihub-test-key provider-secret")
      end

      it "returns a sanitized provider error" do
        expect { script }.to raise_error(described_class::Error, "http_500")
      end
    end
  end

  describe "#generate_terms" do
    let(:terms_inputs) do
      {
        video_subject: "Summer skincare",
        video_script: "A summer story.",
        amount: 2,
        match_materials_to_script: true
      }
    end
    let(:terms_request) do
      stub_request(:post, "http://mpt.test/api/v1/terms")
        .with(
          body: {
            "video_subject" => "Summer skincare",
            "video_script" => "A summer story.",
            "amount" => 2,
            "match_materials_to_script" => true
          }
        )
        .to_return(
          status: 200,
          body: { status: 200, data: { video_terms: [ "sunny bathroom", "skincare bottle" ] } }.to_json
        )
    end

    before { terms_request }
    subject(:terms) { client.generate_terms(**terms_inputs) }

    it "returns the generated scene terms from MPT" do
      expect(terms).to eq("video_terms" => [ "sunny bathroom", "skincare bottle" ])
      expect(terms_request).to have_been_requested.once
    end
  end

  describe "#create_video" do
    let(:correlation_id) { "correlation-123" }
    let(:video_request) do
      stub_request(:post, "http://mpt.test/api/v1/videos")
        .with(body: { "video_source" => "muapi" })
        .to_return(status: 200, body: { status: 200, data: { task_id: "mpt-task-123" } }.to_json)
    end

    before { video_request }
    subject(:response) { client.create_video(payload: { video_source: "muapi" }, task_id: correlation_id) }

    it "returns the task ID and sends the stable correlation ID" do
      expect(response).to eq("task_id" => "mpt-task-123")
      expect(video_request).to have_been_requested.once
      expect(
        a_request(:post, "http://mpt.test/api/v1/videos")
          .with(headers: { "x-task-id" => correlation_id })
      ).to have_been_made.once
    end

    it "does not send an OAuth bearer token to the MPT endpoint" do
      response

      expect(
        a_request(:post, "http://mpt.test/api/v1/videos").with do |request|
          request.headers.keys.none? { |header| header.casecmp("authorization").zero? }
        end
      ).to have_been_made.once
    end

    context "when the correlation ID is missing" do
      let(:correlation_id) { nil }

      it "does not send a video request" do
        expect { response }.to raise_error(described_class::Error, "missing_task_id")
        expect(video_request).not_to have_been_requested
      end
    end
  end

  describe "#task" do
    let(:task_request) do
      stub_request(:get, "http://mpt.test/api/v1/tasks/mpt-task-123")
        .to_return(status: 200, body: { status: 200, data: task_result }.to_json)
    end
    let(:task_result) do
      {
        task_id: "mpt-task-123",
        state: 1,
        videos: [ "clip-1.mp4" ],
        combined_videos: [ "combined.mp4" ],
        audio_file: "audio.wav",
        subtitle_path: "subtitle.srt"
      }
    end

    before { task_request }
    subject(:task) { client.task(task_id: "mpt-task-123") }

    it "returns task state and every generated output reference" do
      expect(task).to eq(task_result.stringify_keys)
      expect(task_request).to have_been_requested.once
    end
  end

  describe "#tasks" do
    let(:task_page) do
      {
        "tasks" => [
          { "task_id" => "mpt-task-123", "request_id" => "correlation-123", "state" => 4 }
        ],
        "total" => 1,
        "page" => 2,
        "page_size" => 1000
      }
    end
    let(:task_list_request) do
      stub_request(:get, "http://mpt.test/api/v1/tasks?page=2&page_size=1000")
        .with(headers: { "x-api-key" => "affihub-test-key" })
        .to_return(status: 200, body: { status: 200, data: task_page }.to_json)
    end

    before { task_list_request }
    subject(:tasks) { client.tasks(page: 2, page_size: 1000) }

    it "returns the requested task page with its correlation IDs" do
      expect(tasks).to eq(task_page)
      expect(task_list_request).to have_been_requested.once
    end
  end

  describe "#download" do
    let(:task_id) { "mpt-task-123" }
    let(:file_path) { "/tasks/mpt-task-123/scene-1.mp4" }
    let(:download_url) { "http://mpt.test/api/v1/download/mpt-task-123/scene-1.mp4" }
    let(:destination) { StringIO.new }
    let(:download_request) do
      stub_request(:get, download_url)
        .with(headers: { "x-api-key" => "affihub-test-key" })
        .to_return(status: 200, body: "scene-video-bytes")
    end

    before { download_request }

    it "streams an artifact from the configured MPT host into the destination" do
      client.download(file_path:, task_id:, destination:)

      expect(destination.string).to eq("scene-video-bytes")
      expect(download_request).to have_been_requested.once
    end

    context "when the artifact reference points to another host" do
      let(:file_path) { "https://files.example.test/tasks/mpt-task-123/scene-1.mp4" }

      it "rejects the reference without requesting the external host" do
        expect { client.download(file_path:, task_id:, destination:) }
          .to raise_error(described_class::Error, "invalid_file_path")
        expect(WebMock).not_to have_requested(:get, file_path)
      end
    end

    context "when the artifact path escapes the task directory" do
      let(:file_path) { "http://mpt.test/api/v1/download/tasks/../secrets.yml" }

      it "rejects the path before making a request" do
        expect { client.download(file_path:, task_id:, destination:) }
          .to raise_error(described_class::Error, "invalid_file_path")
        expect(WebMock).not_to have_requested(:get, file_path)
      end
    end

    context "when an encoded path separator escapes the task directory" do
      let(:file_path) { "http://mpt.test/api/v1/download/tasks/mpt-task-123/scene%2F..%2Fsecrets.yml" }

      it "rejects the encoded traversal before making a request" do
        expect { client.download(file_path:, task_id:, destination:) }
          .to raise_error(described_class::Error, "invalid_file_path")
        expect(WebMock).not_to have_requested(:get, file_path)
      end
    end

    context "when the artifact belongs to another task" do
      let(:file_path) { "http://mpt.test/api/v1/download/tasks/other-task/scene-1.mp4" }

      it "rejects the artifact before making a request" do
        expect { client.download(file_path:, task_id:, destination:) }
          .to raise_error(described_class::Error, "invalid_file_path")
        expect(WebMock).not_to have_requested(:get, file_path)
      end
    end

    context "when the artifact exceeds the configured download limit" do
      let(:download_request) do
        stub_request(:get, download_url)
          .to_return(status: 200, body: "a" * 1_025)
      end

      it "rejects the oversized response without exceeding the configured limit" do
        expect { client.download(file_path:, task_id:, destination:) }
          .to raise_error(described_class::Error, "download_too_large")
        expect(destination.string.bytesize).to be <= 1_024
      end
    end
  end
end
