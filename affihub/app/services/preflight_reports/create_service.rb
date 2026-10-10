# frozen_string_literal: true

class PreflightReports::CreateService < ApplicationService
  attr_reader :preflight_report, :video_project, :render_version

  # Initializes a read-only audit for one immutable render and its selected destinations.
  #
  # @param video_project_id [Integer] the project that owns the render version
  # @param render_version_id [Integer] the render version under review
  # @param social_destination_ids [Array<Integer>] the destinations included in the audit
  # @return [PreflightReports::CreateService] the configured service
  def initialize(video_project_id:, render_version_id:, social_destination_ids:)
    @video_project_id = video_project_id
    @render_version_id = render_version_id
    @social_destination_ids = Array(social_destination_ids).reject(&:blank?).map(&:to_i).uniq
    @workflow_configuration = Rails.application.config_for(:video_workflow).deep_symbolize_keys
    @configuration = @workflow_configuration.fetch(:preflight)
    @youtube_configuration = Rails.application.config_for(:youtube).deep_symbolize_keys
    @mpt_configuration = Rails.application.config_for(:money_printer_turbo).deep_symbolize_keys
    super()
  end

  # Persists an audit snapshot without creating render, publish, or paid AI work.
  #
  # @return [Boolean] whether the scoped audit report was persisted
  def call
    return false unless step_load_render_version
    return false unless step_load_social_destinations

    step_build_project_checks
    step_build_destination_results
    step_persist_report
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  private

  def step_load_render_version
    @video_project = VideoProject.find(@video_project_id)
    @render_version = video_project.render_versions.includes(:source_asset).find(@render_version_id)
    true
  end

  def step_load_social_destinations
    destinations_by_id = SocialDestination.includes(:social_connection)
      .where(id: @social_destination_ids)
      .index_by(&:id)
    @social_destinations = @social_destination_ids.filter_map { |id| destinations_by_id[id] }
    return true if @social_destinations.length == @social_destination_ids.length

    step_fail!("Có destination không tồn tại.")
  end

  def step_build_project_checks
    @project_checks = {
      "source" => step_check_source,
      "render" => step_check_render,
      "worker" => step_check_worker,
      "ai_estimate" => step_check_ai_estimate,
      "paid_ai" => step_check_paid_ai,
      "google_drive" => step_check_not_configured("Google Drive"),
      "google_sheets" => step_check_not_configured("Google Sheets"),
      "publish_readiness" => step_check_publish_readiness
    }
  end

  def step_build_destination_results
    @destination_results = {
      "project" => {
        "status" => @social_destinations.empty? ? "warning" : "ready",
        "checks" => @project_checks
      }
    }
    @social_destinations.each do |social_destination|
      @destination_results[social_destination.id.to_s] = step_destination_result(social_destination)
    end
  end

  def step_persist_report
    @preflight_report = PreflightReport.create!(
      render_version: @render_version,
      checked_destination_ids: @social_destination_ids,
      destination_results: @destination_results,
      checked_at: Time.current
    )
    step_succeed!
    success?
  end

  def step_check_source
    source_asset = @render_version.source_asset
    return step_result(:blocked, "SourceAsset ##{source_asset.id}", "Source chưa ở trạng thái sẵn sàng hoặc thiếu file local.", "Import lại source rồi chờ kiểm tra media hoàn tất.") unless source_asset.ready? && source_asset.file.attached?
    source_file_state = step_attachment_storage_state(source_asset.file)
    return step_result(:blocked, "SourceAsset ##{source_asset.id}", "Source file không còn đọc được từ storage.", "Khôi phục file source trong storage rồi chạy lại kiểm tra media.") if source_file_state == :missing
    return step_result(:unavailable, "SourceAsset ##{source_asset.id}", "Không thể kiểm tra file source trong storage.", "Kiểm tra kết nối và quyền đọc storage rồi chạy lại preflight.") if source_file_state == :unavailable
    return step_result(:unavailable, "SourceAsset ##{source_asset.id}", "Metadata source chưa đủ để xác nhận thời lượng và kích thước.", "Chạy lại kiểm tra media source.") unless source_metadata_valid?(source_asset)

    step_result(:passed, "SourceAsset ##{source_asset.id}", "Source đã được kiểm tra và có file local cùng metadata.", "Không cần khắc phục.", duration_seconds: source_asset.media_metadata.fetch("duration_seconds"))
  end

  def step_check_render
    source_asset = @render_version.source_asset
    return step_result(:blocked, "RenderVersion ##{@render_version.id}", "Render chưa sẵn sàng hoặc thiếu file MP4.", "Chờ render hoàn tất hoặc tạo render version mới.") unless @render_version.ready? && @render_version.file.attached?
    render_file_state = step_attachment_storage_state(@render_version.file)
    return step_result(:blocked, "RenderVersion ##{@render_version.id}", "Render file không còn đọc được từ storage.", "Khôi phục file render trong storage hoặc tạo render version mới.") if render_file_state == :missing
    return step_result(:unavailable, "RenderVersion ##{@render_version.id}", "Không thể kiểm tra file render trong storage.", "Kiểm tra kết nối và quyền đọc storage rồi chạy lại preflight.") if render_file_state == :unavailable

    validator = RenderVersions::EditConfigValidator.new(
      video_project: @render_version.video_project,
      source_asset:,
      edit_config: @render_version.edit_config
    )
    return step_result(:blocked, "RenderVersion ##{@render_version.id}", validator.errors.full_messages.to_sentence.presence || "Timeline hoặc asset được tham chiếu không hợp lệ.", "Mở editor, sửa timeline/asset rồi render version mới.") unless validator.call
    return step_result(:unavailable, "RenderVersion ##{@render_version.id}", "Metadata đầu ra chưa đủ để xác minh profile render.", "Kiểm tra lại file render bằng ffprobe.") unless render_metadata_valid?
    return step_result(:blocked, "RenderVersion ##{@render_version.id}", "Thông số MP4 không khớp profile render MVP.", "Render lại theo profile MP4 H.264/AAC 1080×1920 30 fps.", measured: render_metadata_summary) unless render_metadata_valid?

    step_result(:passed, "RenderVersion ##{@render_version.id}", "File render và timeline khớp profile MVP.", "Không cần khắc phục.", measured: render_metadata_summary)
  end

  def step_check_worker
    workflow_run = step_stale_workflow_run
    if workflow_run
      return step_result(
        :blocked,
        "#{workflow_run.workflowable_type} ##{workflow_run.workflowable_id}",
        "Lease hoặc heartbeat của workflow #{workflow_run.operation} đã quá hạn.",
        "Đối soát workflow trước khi nhận thêm side effect.",
        operation: workflow_run.operation,
        stage: workflow_run.stage,
        worker_id: workflow_run.worker_id,
        heartbeat_at: workflow_run.heartbeat_at&.iso8601,
        lease_expires_at: workflow_run.lease_expires_at&.iso8601
      )
    end

    worker_state = step_live_worker_state
    return step_result(:passed, "Solid Queue worker", "Worker có heartbeat còn hiệu lực.", "Không cần khắc phục.") if worker_state == :running
    return step_result(:blocked, "Solid Queue worker", "Không tìm thấy worker có heartbeat còn hiệu lực.", "Khởi động worker Solid Queue rồi chạy lại preflight.") if worker_state == :stopped

    step_result(:unavailable, "Solid Queue worker", "Không thể đọc registry heartbeat của Solid Queue trong cấu hình hiện tại.", "Kiểm tra cấu hình database queue và quyền đọc trạng thái worker.")
  end

  def step_check_paid_ai
    recovery_verified_at = step_mpt_recovery_verified_at
    recovery_configuration_matches = step_mpt_recovery_configuration_matches?
    recovery_verified = @mpt_configuration.dig(:preflight, :restart_recovery_verified) == true &&
      recovery_verified_at.present? && recovery_verified_at <= Time.current && recovery_configuration_matches
    unless recovery_verified
      return step_result(
        :blocked,
        "MoneyPrinterTurbo recovery",
        "Khả năng lookup/reconcile task sau restart chưa được xác minh cho cấu hình MPT hiện tại.",
        "Chạy smoke test restart/reconcile và chỉ mở gate bằng cấu hình đã được xác minh.",
        restart_recovery_verified: false,
        restart_recovery_verified_at: recovery_verified_at&.iso8601,
        recovery_configuration_matches:
      )
    end

    active_statuses = @configuration.fetch(:active_ai_generation_statuses)
    ai_generations = @render_version.video_project.ai_generations
      .where(status: active_statuses)
      .order(:id)
    if ai_generations.empty?
      return step_result(
        :blocked,
        "MoneyPrinterTurbo recovery",
        "Project chưa có MPT task bền vững để đối soát sau restart.",
        "Xác minh task state bằng smoke test restart/reconcile trước khi mở AI trả phí.",
        restart_recovery_verified: true,
        restart_recovery_verified_at: recovery_verified_at.iso8601,
        recovery_configuration_matches: true
      )
    end

    verified_tasks = ai_generations.map { |ai_generation| step_verify_mpt_task(ai_generation) }
    all_tasks_verified = verified_tasks.all? { |task| task.fetch("status") == "passed" }
    status = all_tasks_verified ? :passed : :blocked
    step_result(
      status,
      "MoneyPrinterTurbo recovery",
      all_tasks_verified ? "Task state đã được đọc lại từ Rails DB và đối soát qua MPT API read-only." : "Có MPT task chưa thể đối soát an toàn sau restart.",
      all_tasks_verified ? "Không cần khắc phục." : "Đối soát task hiện có; không gửi task thay thế.",
      restart_recovery_verified: true,
      restart_recovery_verified_at: recovery_verified_at.iso8601,
      recovery_configuration_matches: true,
      tasks: verified_tasks,
      task_id: verified_tasks.one? ? verified_tasks.first.fetch("task_id") : nil
    )
  rescue Mpt::Client::Error => error
    step_result(:unavailable, "MoneyPrinterTurbo recovery", "Không đọc được task state hiện tại từ MPT.", "Khôi phục kết nối MPT và chạy lại preflight; không gửi task thay thế.", restart_recovery_verified: recovery_verified, restart_recovery_verified_at: recovery_verified_at&.iso8601, recovery_configuration_matches:, provider_error_code: error.code)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError, EOFError
    step_result(:unavailable, "MoneyPrinterTurbo recovery", "MPT không phản hồi khi kiểm tra task state.", "Khôi phục MPT rồi đối soát task hiện có trước khi tiếp tục.", restart_recovery_verified: recovery_verified, restart_recovery_verified_at: recovery_verified_at&.iso8601, recovery_configuration_matches:, provider_error_code: "network_request_failed")
  end

  def step_mpt_recovery_verified_at
    value = @mpt_configuration.dig(:preflight, :restart_recovery_verified_at)
    return if value.blank?

    Time.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def step_mpt_recovery_configuration_matches?
    verified_configuration = @mpt_configuration.dig(:preflight, :restart_recovery_verified_for)
      .to_h
      .deep_symbolize_keys
    current_configuration = @mpt_configuration.slice(:base_url, :version, :commit)
    current_configuration.keys.all? do |key|
      current_configuration.fetch(key).present? && verified_configuration[key] == current_configuration[key]
    end
  end

  def step_check_ai_estimate
    ai_generation = @render_version.video_project.ai_generations
      .where.not(estimate_snapshot: {})
      .order(:updated_at, :id)
      .last
    return step_result(:warning, "AI estimate", "Project chưa có estimate AI đã lưu.", "Preflight không tạo estimate mới hoặc phát sinh chi phí.") unless ai_generation

    estimate = ai_generation.estimate_snapshot.to_h.deep_symbolize_keys
    cost_breakdown = estimate.fetch(:cost_breakdown, {}).to_h
    sources = cost_breakdown.values.filter_map do |provider_cost|
      provider_cost.to_h.deep_symbolize_keys[:source].presence
    end.uniq
    step_result(
      :warning,
      "AI estimate",
      "Estimate đã lưu chỉ mang tính tham khảo và không giữ giá.",
      "Xem nguồn và thời điểm estimate trước khi xác nhận tác vụ AI trả phí.",
      total_amount: estimate[:total_amount],
      currency: estimate[:currency],
      required_costs_known: estimate[:required_costs_known],
      estimated_at: estimate[:estimated_at],
      sources:,
      cost_breakdown:
    )
  end

  def step_check_not_configured(integration_name)
    step_result(:not_configured, integration_name, "Integration chưa được kết nối trong MVP hiện tại.", "Kết nối integration nếu muốn dùng luồng đồng bộ này.")
  end

  def step_check_publish_readiness
    return step_result(:warning, @render_version.video_project.name, "Chưa chọn Page, kênh hoặc tài khoản đích để kiểm tra khả năng đăng.", "Chọn destination rồi chạy preflight trước khi tạo Publication.") if @social_destinations.empty?

    step_result(:passed, @render_version.video_project.name, "Đã chọn #{@social_destinations.length} destination để kiểm tra riêng.", "Xem readiness trong từng destination.")
  end

  def step_destination_result(social_destination)
    connector_check = step_check_connector(social_destination)
    provider_result = step_check_provider(social_destination, connector_check:)
    checks = @project_checks.slice("source", "render", "worker")
      .merge("connector" => connector_check)
      .merge("media_transfer" => step_check_media_transfer(social_destination))
      .merge(provider_result.fetch(:checks))
    required_check_keys = %w[source render worker connector media_transfer] + provider_result.fetch(:blocking_check_keys)
    required_checks = checks.slice(*required_check_keys).values
    status = if required_checks.any? { |check| check.fetch("status") == "blocked" }
      "blocked"
    elsif required_checks.any? { |check| check.fetch("status") != "passed" }
      "unavailable"
    else
      "ready"
    end

    { "status" => status, "checks" => checks }
  end

  def step_check_connector(social_destination)
    social_connection = social_destination.social_connection
    provider_configuration = step_provider_configuration(social_destination.provider)
    required_scopes = step_required_scopes(social_destination.provider, provider_configuration)
    has_required_scopes = (required_scopes - social_connection.scopes).empty?
    tokens_current = token_current?(social_connection.token_expires_at) && token_current?(social_destination.token_expires_at)
    connected = social_connection.connected? && social_destination.connected? && tokens_current
    return step_result(:blocked, social_destination.name, "Kết nối hoặc token destination chưa sẵn sàng.", "Kết nối lại account/Page/kênh rồi chạy lại preflight.") unless connected
    return step_result(:blocked, social_destination.name, "OAuth connection thiếu scope cần thiết cho thao tác publish.", "Cấp lại quyền publish theo danh sách scope đã cấu hình.", required_scopes:) unless has_required_scopes

    step_result(:passed, social_destination.name, "Kết nối, token và scope publish đang sẵn sàng.", "Không cần khắc phục.")
  end

  def step_check_media_transfer(social_destination)
    provider = social_destination.provider
    configuration = step_media_transfer_configuration(provider)
    missing_configuration = step_missing_media_transfer_configuration(provider, configuration)
    return step_result(
      :unavailable,
      social_destination.name,
      "Chưa thể xác nhận cấu hình chuyển file media cho destination này.",
      "Kiểm tra cấu hình upload local của connector rồi chạy lại preflight.",
      missing_configuration: missing_configuration.to_s
    ) if missing_configuration

    step_result(
      :passed,
      social_destination.name,
      "Cấu hình chuyển file media local đã sẵn sàng; preflight không mở phiên upload.",
      "Không cần khắc phục.",
      protocol: configuration.fetch(:media_transfer_protocol)
    )
  rescue KeyError => error
    step_result(
      :unavailable,
      social_destination.name,
      "Thiếu cấu hình chuyển file media cho destination này.",
      "Kiểm tra cấu hình upload local của connector rồi chạy lại preflight.",
      missing_configuration: error.key.to_s
    )
  end

  def step_media_transfer_configuration(provider)
    return @youtube_configuration if provider == "youtube"
    return step_provider_configuration(provider) if %w[facebook instagram tiktok].include?(provider)

    {}
  end

  def step_missing_media_transfer_configuration(provider, configuration)
    required_keys = case provider
    when "facebook"
      %i[media_transfer_protocol graph_api_base_url api_version upload_timeout_seconds]
    when "instagram"
      %i[media_transfer_protocol graph_api_base_url api_version instagram_upload_type upload_timeout_seconds]
    when "tiktok"
      %i[media_transfer_protocol api_base_url api_paths upload_source upload_host_suffix upload_chunk_size_bytes upload_max_chunks]
    when "youtube"
      %i[media_transfer_protocol api_version upload_base_url upload_session_id_parameter oauth]
    else
      return :provider
    end
    missing_key = required_keys.find { |key| configuration[key].blank? }
    return missing_key if missing_key
    return :instagram_upload_type if provider == "instagram" && configuration.fetch(:instagram_upload_type) != "resumable"
    return :upload_source if provider == "tiktok" && configuration.fetch(:upload_source) != "FILE_UPLOAD"
    return :initialize_video_publish_endpoint if provider == "tiktok" && configuration.dig(:api_paths, :initialize_video_publish).blank?
    return :youtube_upload_timeout_seconds if provider == "youtube" && !configuration.dig(:oauth, :upload_timeout_seconds).to_i.positive?
    return :upload_timeout_seconds if %w[facebook instagram].include?(provider) && !configuration.fetch(:upload_timeout_seconds).to_i.positive?

    nil
  end

  def step_check_provider(social_destination, connector_check:)
    case social_destination.provider
    when "facebook"
      step_check_facebook(social_destination, connector_check:)
    when "instagram"
      step_check_instagram(social_destination, connector_check:)
    when "tiktok"
      step_check_tiktok(social_destination, connector_check:)
    when "youtube"
      step_check_youtube(social_destination)
    else
      { checks: { "provider" => step_result(:unavailable, social_destination.name, "Provider chưa được cấu hình.", "Chọn provider được hỗ trợ trong MVP.") }, blocking_check_keys: [ "provider" ] }
    end
  end

  def step_check_facebook(social_destination, connector_check:)
    unless connector_check.fetch("status") == "passed"
      return {
        checks: { "permissions" => step_result(:unavailable, social_destination.name, "Không thể kiểm tra quyền Page khi connection chưa sẵn sàng.", "Kết nối lại Facebook rồi kiểm tra quyền Page.") },
        blocking_check_keys: [ "permissions" ]
      }
    end

    pages = Meta::Client.new(provider: :facebook).pages(access_token: social_destination.social_connection.access_token)
    page = pages.find { |candidate| candidate.fetch("id", nil).to_s == social_destination.external_id.to_s }
    can_publish = page.present? && SocialDestination.can_create_content?(page.fetch("tasks", []), provider: :facebook)
    check = if can_publish
      step_result(:passed, social_destination.name, "Meta xác nhận Page có quyền tạo nội dung.", "Không cần khắc phục.")
    else
      step_result(:blocked, social_destination.name, "Không đọc được Page hoặc Page chưa cấp quyền tạo nội dung.", "Cấp quyền tạo nội dung cho Page đã chọn rồi kết nối lại.")
    end
    { checks: { "permissions" => check }, blocking_check_keys: [ "permissions" ] }
  rescue Meta::Client::Error => error
    {
      checks: { "permissions" => step_result(:unavailable, social_destination.name, "Meta không xác nhận được quyền Page hiện tại.", "Khôi phục quyền đọc Meta rồi chạy lại preflight.", provider_error_code: error.code) },
      blocking_check_keys: [ "permissions" ]
    }
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError, EOFError
    {
      checks: { "permissions" => step_result(:unavailable, social_destination.name, "Meta không phản hồi khi kiểm tra quyền Page.", "Khôi phục kết nối Meta rồi chạy lại preflight.", provider_error_code: "network_request_failed") },
      blocking_check_keys: [ "permissions" ]
    }
  end

  def step_check_instagram(social_destination, connector_check:)
    unless connector_check.fetch("status") == "passed"
      return {
        checks: { "publishing_cap" => step_result(:unavailable, social_destination.name, "Không thể kiểm tra giới hạn đăng khi connection chưa sẵn sàng.", "Kết nối lại Instagram/Page rồi chạy lại preflight.", quota_usage: nil, quota_total: nil) },
        blocking_check_keys: [ "publishing_cap" ]
      }
    end

    response = Meta::Client.new(provider: :instagram).instagram_content_publishing_limit(
      instagram_user_id: social_destination.external_id,
      page_access_token: social_destination.access_token
    )
    quota = response.fetch("data", []).first.to_h
    quota_configuration = quota.fetch("config", {}).to_h
    quota_usage = step_integer(quota["quota_usage"])
    quota_total = step_integer(quota_configuration["quota_total"])
    quota_duration = step_integer(quota_configuration["quota_duration"])
    return step_instagram_quota_unavailable(social_destination, "Meta chưa trả usage/cap/duration hiện hành.") if [ quota_usage, quota_total, quota_duration ].any?(&:nil?)

    exhausted = quota_usage >= quota_total
    check = step_result(
      exhausted ? :blocked : :passed,
      social_destination.name,
      exhausted ? "Instagram báo đã chạm content publishing limit hiện hành." : "Đã đọc content publishing limit hiện hành từ Instagram.",
      exhausted ? "Chờ giới hạn hiện hành của Instagram mở lại rồi chạy preflight." : "Không cần khắc phục.",
      quota_usage:,
      quota_total:,
      quota_duration_seconds: quota_duration
    )
    { checks: { "publishing_cap" => check }, blocking_check_keys: [ "publishing_cap" ] }
  rescue Meta::Client::Error => error
    step_instagram_quota_unavailable(social_destination, "Instagram không trả được giới hạn đăng hiện hành.", provider_error_code: error.code)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError, EOFError
    step_instagram_quota_unavailable(social_destination, "Instagram không phản hồi khi kiểm tra giới hạn đăng.", provider_error_code: "network_request_failed")
  end

  def step_instagram_quota_unavailable(social_destination, reason, provider_error_code: nil)
    check = step_result(
      :unavailable,
      social_destination.name,
      reason,
      "Khôi phục quyền đọc Instagram rồi kiểm tra lại; không dùng quota hardcode.",
      quota_usage: nil,
      quota_total: nil,
      provider_error_code:
    )
    { checks: { "publishing_cap" => check }, blocking_check_keys: [ "publishing_cap" ] }
  end

  def step_check_tiktok(social_destination, connector_check:)
    checks = { "content_policy" => step_tiktok_content_policy_check(social_destination) }
    local_cap_check = step_tiktok_local_cap_check(social_destination)
    if local_cap_check.fetch("status") == "blocked"
      checks["publishing_cap"] = local_cap_check
      return { checks:, blocking_check_keys: [ "content_policy", "publishing_cap" ] }
    end

    unless connector_check.fetch("status") == "passed"
      checks["publishing_cap"] = step_tiktok_counter_unavailable(
        social_destination,
        "Không thể đọc Creator Info khi connection chưa sẵn sàng."
      )
      return { checks:, blocking_check_keys: [ "content_policy", "publishing_cap" ] }
    end

    response = TikTok::Client.new.creator_info(access_token: social_destination.access_token)
    error_code = response.dig("error", "code") if response.is_a?(Hash)
    provider_configuration = step_provider_configuration(:tiktok)
    cap_errors = provider_configuration.fetch(:provider_cap_errors)
    if cap_errors.value?(error_code)
      checks.merge!(step_tiktok_provider_cap(social_destination, error_code, cap_errors).fetch(:checks))
      return { checks:, blocking_check_keys: [ "content_policy", "publishing_cap" ] }
    end

    unless error_code == provider_configuration.fetch(:successful_response_code)
      checks["publishing_cap"] = step_tiktok_counter_unavailable(
        social_destination,
        "TikTok không xác nhận được Creator Info hiện tại.",
        provider_error_code: error_code
      )
      return { checks:, blocking_check_keys: [ "content_policy", "publishing_cap" ] }
    end

    checks["publishing_cap"] = step_tiktok_counter_unavailable(
      social_destination,
      "TikTok không cung cấp số bài đã dùng, số còn lại hoặc thời điểm đặt lại."
    )
    { checks:, blocking_check_keys: [ "content_policy" ] }
  rescue TikTok::Client::Error => error
    checks["publishing_cap"] = step_tiktok_counter_unavailable(
      social_destination,
      "TikTok không trả được Creator Info.",
      provider_error_code: error.code
    )
    { checks:, blocking_check_keys: [ "content_policy", "publishing_cap" ] }
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError, EOFError
    checks["publishing_cap"] = step_tiktok_counter_unavailable(
      social_destination,
      "TikTok không phản hồi khi kiểm tra Creator Info.",
      provider_error_code: "network_request_failed"
    )
    { checks:, blocking_check_keys: [ "content_policy", "publishing_cap" ] }
  end

  def step_tiktok_content_policy_check(social_destination)
    disallowed_types = @configuration.fetch(:tiktok_disallowed_overlay_types)
    overlays = @render_version.edit_config.to_h.fetch("overlays", [])
    disallowed_overlays = overlays.select do |overlay|
      overlay.is_a?(Hash) && disallowed_types.include?(overlay["type"])
    end
    overlay_types = disallowed_overlays.map { |overlay| overlay.fetch("type") }.uniq
    return step_result(:passed, social_destination.name, "Render không chứa logo hoặc overlay quảng bá do AffiHub thêm.", "Không cần khắc phục.", overlay_types:) if overlay_types.empty?

    step_result(
      :blocked,
      social_destination.name,
      "TikTok không cho phép logo hoặc overlay quảng bá do AffiHub thêm vào media.",
      "Mở editor, bỏ logo/overlay quảng bá rồi tạo render version mới cho TikTok.",
      overlay_types:
    )
  end

  def step_tiktok_local_cap_check(social_destination)
    provider_configuration = step_provider_configuration(:tiktok)
    cap = provider_configuration.fetch(:max_distinct_creators_per_24_hours).to_i
    window = provider_configuration.fetch(:max_distinct_creators_window_seconds).to_i.seconds
    recent_creator_ids = SocialConnection.with_publish_attempt_since(
      provider: "tiktok",
      operation: provider_configuration.fetch(:publication_operation),
      stage: provider_configuration.fetch(:publish_stage),
      since: Time.current - window
    ).pluck(:id)
    already_has_slot = recent_creator_ids.include?(social_destination.social_connection_id)
    cap_reached = !already_has_slot && recent_creator_ids.length >= cap
    return step_result(:passed, social_destination.name, "AffiHub local poster cap còn chỗ cho creator này.", "Không cần khắc phục.", observed_posters: recent_creator_ids.length, local_cap: cap) unless cap_reached

    step_result(
      :blocked,
      social_destination.name,
      "AffiHub đã dùng đủ số poster TikTok khác nhau cho phép trong cửa sổ 24 giờ.",
      "Chờ cửa sổ cap local trượt qua trước khi đăng bằng creator mới.",
      observed_posters: recent_creator_ids.length,
      local_cap: cap,
      provider_error_code: provider_configuration.fetch(:safe_error_codes).fetch(:app_local_cap_reached)
    )
  end

  def step_tiktok_provider_cap(social_destination, error_code, cap_errors)
    creator_cap = error_code == cap_errors.fetch(:creator)
    reason = creator_cap ? "TikTok báo creator đã chạm giới hạn đăng." : "TikTok báo app đã chạm active creator cap."
    action = creator_cap ? "Chờ TikTok xác nhận có thể đăng lại; không ước lượng giờ reset." : "Chờ app quota được TikTok mở lại; không gửi Direct Post."
    check = step_result(
      :blocked,
      social_destination.name,
      reason,
      action,
      provider_error_code: error_code,
      remaining_count: nil,
      reset_at: nil
    )
    { checks: { "publishing_cap" => check }, blocking_check_keys: [ "publishing_cap" ] }
  end

  def step_tiktok_counter_unavailable(social_destination, reason, provider_error_code: nil)
    step_result(
      :unavailable,
      social_destination.name,
      reason,
      "TikTok sẽ được kiểm tra lại ngay trước Direct Post.",
      provider_error_code:,
      remaining_count: nil,
      reset_at: nil
    )
  end

  def step_check_youtube(social_destination)
    quota_configuration = @youtube_configuration.fetch(:quota)
    usage_date = Time.current.in_time_zone(quota_configuration.fetch(:timezone)).to_date
    operations = quota_configuration.fetch(:buckets).values.to_h do |bucket_configuration|
      operation = bucket_configuration.fetch(:method).to_s
      daily_limit = bucket_configuration.fetch(:daily_limit).to_i
      counter = YoutubeQuotaCounter.find_by(bucket: operation, usage_date:)
      observed_count = counter&.requests_count || quota_configuration.fetch(:counter_initial_count).to_i
      operation_status = observed_count >= daily_limit ? :blocked : :passed
      reason = operation_status == :blocked ? "Quota local của #{operation} đã đạt giới hạn đang cấu hình." : "Quota local của #{operation} chưa đạt giới hạn đang cấu hình."
      action = operation_status == :blocked ? "Chờ quota bucket này mở lại theo nguồn limit hiện hành." : "Không cần khắc phục."
      [ operation, step_result(operation_status, "YouTube #{operation}", reason, action, observed_count:, daily_limit:) ]
    end
    publish_operation = quota_configuration.fetch(:publish_operation).to_s
    publish_status = operations.fetch(publish_operation).fetch("status")
    publish_blocked = publish_status == "blocked"
    any_non_publish_operation_blocked = operations.any? do |operation, check|
      operation != publish_operation && check.fetch("status") == "blocked"
    end
    quota_status = if publish_blocked
      :blocked
    elsif any_non_publish_operation_blocked
      :warning
    else
      :passed
    end
    quota_check = step_result(
      quota_status,
      "YouTube Data API v3 quota",
      "AffiHub đếm riêng request theo method; app khác có thể dùng chung quota project.",
      publish_blocked ? "Chờ bucket videos.insert mở lại rồi chạy preflight." : "Google Cloud Console là nguồn tổng usage authoritative.",
      operations:,
      limit_source_url: quota_configuration.fetch(:limit_source_url),
      console_url: quota_configuration.fetch(:console_url),
      scope_notice: "Bộ đếm chỉ gồm request do AffiHub tạo; Google Cloud Console là nguồn tổng usage authoritative."
    )
    blocking_check_keys = publish_blocked ? [ "quota" ] : []
    { checks: { "quota" => quota_check }, blocking_check_keys: }
  end

  def step_stale_workflow_run
    workflow_runs = step_project_workflow_runs
    running_workflows = workflow_runs.running
    checked_at = Time.current
    heartbeat_since = checked_at - @configuration.fetch(:worker_heartbeat_timeout_seconds).to_i.seconds
    stale_lease_runs = running_workflows.where(lease_expires_at: nil)
      .or(running_workflows.where(lease_expires_at: ..checked_at))
    stale_heartbeat_runs = running_workflows.where(heartbeat_at: nil)
      .or(running_workflows.where(heartbeat_at: ..heartbeat_since))
    stale_lease_runs.or(stale_heartbeat_runs)
      .order(:lease_expires_at, :id)
      .first
  end

  def step_project_workflow_runs
    project = @render_version.video_project
    workflow_run_scopes = [
      WorkflowRun.where(workflowable: project),
      WorkflowRun.where(workflowable_type: SourceAsset.polymorphic_name, workflowable_id: project.source_assets.select(:id)),
      WorkflowRun.where(workflowable_type: RenderVersion.polymorphic_name, workflowable_id: project.render_versions.select(:id)),
      WorkflowRun.where(workflowable_type: AiGeneration.polymorphic_name, workflowable_id: project.ai_generations.select(:id)),
      WorkflowRun.where(
        workflowable_type: AiGenerationScene.polymorphic_name,
        workflowable_id: AiGenerationScene.joins(:ai_generation).where(ai_generations: { video_project_id: project.id }).select(:id)
      ),
      WorkflowRun.where(
        workflowable_type: Publication.polymorphic_name,
        workflowable_id: Publication.joins(:render_version).where(render_versions: { video_project_id: project.id }).select(:id)
      )
    ]
    workflow_run_scopes.drop(1).reduce(workflow_run_scopes.first) do |combined_scope, workflow_run_scope|
      combined_scope.or(workflow_run_scope)
    end
  end

  # Isolates an unavailable queue registry so report persistence can continue.
  def step_live_worker_state
    SolidQueue::Process.transaction(requires_new: true) do
      heartbeat_since = Time.current - @configuration.fetch(:worker_heartbeat_timeout_seconds).to_i.seconds
      active_worker = SolidQueue::Process.where(kind: @configuration.fetch(:worker_process_kind))
        .where(last_heartbeat_at: heartbeat_since..Time.current)
        .exists?
      active_worker ? :running : :stopped
    end
  rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
    :unavailable
  end

  def step_provider_configuration(provider)
    SocialConnections::ProviderConfiguration.for(provider)
  end

  def step_required_scopes(provider, provider_configuration)
    return @youtube_configuration.fetch(:oauth).fetch(:required_publish_scopes) if provider == "youtube"

    provider_configuration.fetch(:required_publish_scopes, provider_configuration.fetch(:scopes, []))
  end

  def step_result(status_key, subject, reason, action, **details)
    {
      "status" => status_key.to_s,
      "subject" => subject,
      "reason" => reason,
      "action" => action
    }.merge(details.stringify_keys)
  end

  def token_current?(expires_at)
    expires_at.blank? || expires_at > Time.current
  end

  def source_metadata_valid?(source_asset)
    metadata = source_asset.media_metadata.to_h
    duration = step_number(metadata["duration_seconds"])
    width = step_integer(metadata["width"])
    height = step_integer(metadata["height"])
    duration&.positive? && width&.positive? && height&.positive?
  end

  def render_metadata_valid?
    metadata = @render_version.metadata.to_h
    expected_profile = @workflow_configuration.fetch(:render_profile)
    actual_rate = step_frame_rate(metadata["frame_rate"])
    metadata["width"] == expected_profile.fetch(:width) &&
      metadata["height"] == expected_profile.fetch(:height) &&
      actual_rate == expected_profile.fetch(:frame_rate).to_f &&
      metadata["video_codec"] == @configuration.fetch(:output_video_codec) &&
      (metadata["has_audio"] != true || metadata["audio_codec"] == @configuration.fetch(:output_audio_codec))
  end

  def render_metadata_summary
    metadata = @render_version.metadata.to_h
    metadata.slice("width", "height", "frame_rate", "video_codec", "audio_codec", "has_audio", "duration_seconds")
  end

  def step_number(value)
    Float(value, exception: false)
  end

  # Checks storage metadata without downloading the full media file.
  def step_attachment_storage_state(attachment)
    attachment.blob.service.exist?(attachment.blob.key) ? :available : :missing
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError, EOFError
    :unavailable
  end

  def step_integer(value)
    Integer(value, exception: false)
  end

  def step_frame_rate(value)
    return step_number(value) if value.is_a?(Numeric)

    numerator, denominator = value.to_s.split("/", 2)
    return step_number(numerator) if denominator.nil?

    divisor = step_number(denominator)
    return unless divisor&.positive?

    step_number(numerator) / divisor
  end

  def step_verify_mpt_task(ai_generation)
    return { "status" => "blocked", "generation_id" => ai_generation.id, "task_id" => nil } if ai_generation.task_id.blank?

    task = (@mpt_client ||= Mpt::Client.new).task(task_id: ai_generation.task_id)
    task_matches = task.fetch("task_id", nil).to_s == ai_generation.task_id && task.key?("state")
    {
      "status" => task_matches ? "passed" : "blocked",
      "generation_id" => ai_generation.id,
      "task_id" => ai_generation.task_id,
      "provider_state" => task["state"]
    }
  end
end
