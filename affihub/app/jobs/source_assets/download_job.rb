require "fileutils"
require "tmpdir"
require "timeout"

class SourceAssets::DownloadJob < ApplicationJob
  MAX_FILE_SIZE_BYTES = YtDlp::Client::CONFIGURATION.fetch(:max_file_size_bytes)

  queue_as :default

  # Downloads a persisted URL source through its own bounded egress proxy.
  #
  # @param source_asset_id [Integer] the URL source to download
  # @return [Boolean] whether a downloaded file was attached and queued for inspection
  def perform(source_asset_id)
    @source_asset = SourceAsset.find_by(id: source_asset_id)
    return false unless step_claim_source
    return false unless step_reserve_download_slot

    step_download_and_attach
    true
  rescue YtDlp::Client::Error => error
    step_mark_source_failed(error.code)
    false
  rescue SourceAssets::DownloadEgressProxy::BlockedDestination
    step_mark_source_failed("blocked_destination")
    false
  rescue ActiveStorage::Error, Timeout::Error, SocketError, SystemCallError, IOError
    step_mark_source_failed("download_failed")
    false
  ensure
    @proxy&.stop
    FileUtils.remove_entry(@working_directory) if @working_directory && File.directory?(@working_directory)
  end

  private

  def step_claim_source
    return false unless @source_asset

    claimed = false
    @source_asset.with_lock do
      if (@source_asset.pending? || @source_asset.waiting_for_download_slot?) &&
          @source_asset.source_type == "url_download"
        @source_asset.update!(status: :processing, download_error_code: nil, download_error: nil)
        claimed = true
      end
    end
    claimed
  end

  def step_reserve_download_slot
    reservation = SourceAssets::ReserveDownloadSlotService.new
    return true if reservation.call

    @source_asset.update!(
      status: :waiting_for_download_slot,
      download_error_code: "download_slot_limit",
      download_error: "Đã chạm giới hạn lượt tải. AffiHub sẽ thử lại khi có lượt trống."
    )
    self.class.set(wait_until: reservation.next_available_at).perform_later(@source_asset.id)
    false
  end

  def step_download_and_attach
    @working_directory = Dir.mktmpdir("affihub-source-download")
    @proxy = SourceAssets::DownloadEgressProxy.new
    proxy_url = @proxy.start
    output_template = File.join(@working_directory, "source.%(ext)s")
    YtDlp::Client.new(proxy_url:).download(url: @source_asset.source_url, output_path: output_template)
    output_path = step_downloaded_file
    step_attach_download(output_path)
    @source_asset.update!(status: :pending, download_error_code: nil, download_error: nil)
    SourceAssets::InspectJob.perform_later(@source_asset.id)
  end

  def step_downloaded_file
    output_files = Dir.glob(File.join(@working_directory, "source.*")).select do |path|
      File.file?(path) && File.basename(path).match?(/\Asource\.[a-z0-9]{1,10}\z/i)
    end
    raise YtDlp::Client::Error, "download_failed" unless output_files.one?

    output_path = output_files.first
    raise YtDlp::Client::Error, "download_failed" unless File.size?(output_path)
    raise YtDlp::Client::Error, "file_too_large" if File.size(output_path) > MAX_FILE_SIZE_BYTES
    raise YtDlp::Client::Error, "download_failed" unless step_inside_working_directory?(output_path)

    output_path
  end

  def step_inside_working_directory?(path)
    root = File.realpath(@working_directory)
    real_path = File.realpath(path)
    real_path.start_with?("#{root}#{File::SEPARATOR}")
  rescue Errno::ENOENT, SystemCallError
    false
  end

  def step_attach_download(path)
    File.open(path, "rb") do |file|
      @source_asset.file.attach(io: file, filename: File.basename(path))
    end
  end

  def step_mark_source_failed(code)
    return unless @source_asset&.persisted?

    @source_asset.update!(status: :failed, download_error_code: code, download_error: step_failure_message(code))
  end

  def step_failure_message(code)
    prefix = case code
    when "rate_limited"
      "Nguồn đang giới hạn lượt tải tự động."
    when "timeout"
      "Tải video tự động đã quá thời gian cho phép."
    else
      "AffiHub không thể tải video tự động."
    end
    "#{prefix} Hãy lấy file MP4 hoặc MOV bằng công cụ được chủ sở hữu cho phép rồi nhập file thủ công."
  end
end
