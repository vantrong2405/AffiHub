# frozen_string_literal: true

require "tempfile"
require "uri"

module YtDlp
  class Client
    CONFIGURATION = Rails.application.config_for(:yt_dlp).deep_symbolize_keys

    class Error < StandardError
      attr_reader :code

      # Initializes a downloader error with a safe reason code.
      #
      # @param code [String] the sanitized downloader error code
      # @return [YtDlp::Client::Error] the downloader error
      def initialize(code)
        @code = code
        super(code)
      end
    end

    # Initializes the downloader with a job-scoped local egress proxy.
    #
    # @param proxy_url [String] the proxy URL opened for the current job
    # @return [YtDlp::Client] the configured downloader client
    def initialize(proxy_url:)
      @proxy_url = proxy_url
    end

    # Downloads one URL to a worker-owned output path through the local egress proxy.
    #
    # @param url [String] the validated source URL
    # @param output_path [String] the worker-generated output template
    # @return [String] the output template passed to the downloader
    def download(url:, output_path:)
      process_id = nil
      error_output = Tempfile.new("affihub-yt-dlp-stderr")
      process_id = Process.spawn(
        { "LANG" => "C", "PATH" => ENV.fetch("PATH", "/usr/bin:/bin") },
        *step_arguments(url:, output_path:, proxy_url: @proxy_url),
        out: File::NULL,
        err: error_output,
        pgroup: true,
        close_others: true,
        unsetenv_others: true
      )
      step_wait_for_process(process_id, error_output)
      process_id = nil
      output_path
    rescue Errno::ENOENT
      raise Error, "downloader_unavailable"
    ensure
      step_terminate_process(process_id) if process_id
      error_output&.close!
    end

    private

    def step_arguments(url:, output_path:, proxy_url:)
      step_validate_proxy_url(proxy_url)
      arguments = [
        CONFIGURATION.fetch(:command),
        "--no-config",
        "--no-playlist",
        "--proxy", proxy_url,
        "--socket-timeout", CONFIGURATION.fetch(:socket_timeout_seconds).to_s,
        "--retries", CONFIGURATION.fetch(:retries).to_s,
        "--fragment-retries", CONFIGURATION.fetch(:fragment_retries).to_s,
        "--max-filesize", CONFIGURATION.fetch(:max_file_size_bytes).to_s
      ]
      CONFIGURATION.fetch(:native_downloaders).each do |downloader|
        arguments.concat([ "--downloader", downloader ])
      end
      arguments.concat([ "--output", output_path, "--", url ])
    end

    def step_validate_proxy_url(proxy_url)
      proxy = URI.parse(proxy_url)
      valid_proxy = proxy.scheme == "http" && proxy.host == "127.0.0.1" && proxy.port.positive?
      raise Error, "invalid_egress_proxy" unless valid_proxy
    rescue URI::InvalidURIError
      raise Error, "invalid_egress_proxy"
    end

    def step_wait_for_process(process_id, error_output)
      deadline = monotonic_time + CONFIGURATION.fetch(:timeout_seconds)
      loop do
        waited_process_id, process_status = Process.wait2(process_id, Process::WNOHANG)
        return if waited_process_id && process_status.success?
        raise Error, step_error_code(error_output) if waited_process_id
        raise Error, "timeout" if monotonic_time >= deadline

        sleep(0.05)
      end
    rescue Error => error
      step_terminate_process(process_id) if error.code == "timeout"
      raise
    rescue Errno::ECHILD
      raise Error, "process_unavailable"
    end

    def step_error_code(error_output)
      error_output.rewind
      error = error_output.read(65_536).downcase
      return "rate_limited" if error.match?(/\b429\b|too many requests|rate.?limit|blocked/)
      return "unsupported_url" if error.match?(/unsupported url|not a valid url/)

      "download_failed"
    end

    def step_terminate_process(process_id)
      Process.kill("TERM", -process_id)
    rescue Errno::ESRCH
      nil
    ensure
      step_reap_process(process_id)
    end

    def step_reap_process(process_id)
      deadline = monotonic_time + 1
      loop do
        waited_process_id, = Process.wait2(process_id, Process::WNOHANG)
        return if waited_process_id
        break if monotonic_time >= deadline

        sleep(0.05)
      end
      Process.kill("KILL", -process_id)
      Process.wait(process_id)
    rescue Errno::ECHILD, Errno::ESRCH
      nil
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
