# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe YtDlp::Client, type: :client do
  describe "#download" do
    let(:directory) { Dir.mktmpdir("fake-yt-dlp") }
    let(:arguments_path) { File.join(directory, "arguments.txt") }
    let(:output_path) { File.join(directory, "source.mp4") }
    let(:proxy_url) { "http://127.0.0.1:8899" }
    let(:url) { "https://www.youtube.com/watch?v=video-123" }
    let(:original_path) { ENV.fetch("PATH") }
    before do
      executable = File.join(directory, "yt-dlp")
      File.write(executable, <<~SCRIPT)
        #!/usr/bin/env ruby
        File.write(#{arguments_path.dump}, ARGV.join("\\n"))
      SCRIPT
      FileUtils.chmod(0o755, executable)
      ENV["PATH"] = "#{directory}:#{original_path}"
    end

    after do
      ENV["PATH"] = original_path
      FileUtils.remove_entry(directory)
    end

    it "passes the URL as one argument through the bounded HTTPS proxy" do
      described_class.new(proxy_url:).download(url:, output_path:)
      arguments = File.readlines(arguments_path).map(&:chomp)

      expect(arguments).to include(
        "--no-config",
        "--no-playlist",
        "--downloader",
        "http:native",
        "--downloader",
        "m3u8:native",
        "--downloader",
        "dash:native",
        "--proxy",
        proxy_url,
        "--socket-timeout",
        "5",
        "--retries",
        "1",
        "--fragment-retries",
        "1",
        "--max-filesize",
        "1073741824",
        "--output",
        output_path
      )
      expect(arguments.last).to eq(url)
    end
  end
end
