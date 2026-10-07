# frozen_string_literal: true

class AiGenerations::SubmitService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:money_printer_turbo).deep_symbolize_keys
  PROFILE = CONFIGURATION.fetch(:generation_profile)
  SUBMISSION_STAGE = "mpt_video_submission"

  attr_reader :ai_generation, :outbound_attempt, :task_id, :video_request, :workflow_run

  # Initializes a new MPT submission or a recovery for an existing generation.
  #
  # @param inputs [Hash, nil] the approved subject, script, and scene prompts
  # @param estimate [Hash, nil] the displayed cost estimate and input snapshot
  # @param budget [String, Numeric, nil] the user-set maximum cost
  # @param confirmed [Boolean] whether the user confirmed the current estimate
  # @param video_project [VideoProject, nil] the project receiving a new generation
  # @param ai_generation_id [Integer, nil] the persisted generation to reconcile
  # @return [AiGenerations::SubmitService] the configured service
  def initialize(inputs: nil, estimate: nil, budget: nil, confirmed: false, video_project: nil, ai_generation_id: nil)
    @inputs = inputs.to_h.deep_symbolize_keys
    @estimate = estimate.to_h.deep_symbolize_keys
    @budget = budget
    @confirmed = confirmed
    @video_project = video_project
    @ai_generation_id = ai_generation_id
    super()
  end

  # Persists and submits an approved generation, or reconciles its saved MPT request.
  #
  # @return [Boolean] whether MPT accepted or an existing task was recovered
  def call
    return step_recover_submission if @ai_generation_id.present?
    return false unless step_validate_submission
    return false unless step_prepare_submission
    return false unless step_claim_submission
    return false unless step_start_outbound_attempt

    step_submit_video
  end

  private

  def step_validate_submission
    return step_fail!("Cần xác nhận báo giá hiện tại trước khi tạo video.") unless @confirmed == true
    return step_fail!("Báo giá không còn khớp với input hiện tại.") unless @estimate[:input_snapshot] == @inputs
    return step_fail!("Còn khoản phí bắt buộc chưa có báo giá.") unless @estimate[:required_costs_known] == true

    estimated_amount = money_amount(@estimate[:total_amount])
    budget_amount = money_amount(@budget)
    return step_fail!("Cần có tổng báo giá và ngân sách hợp lệ.") unless estimated_amount && budget_amount
    return step_fail!("Tổng báo giá vượt ngân sách của job.") if estimated_amount > budget_amount
    return step_fail!("Cần duyệt từng gợi ý cảnh trước khi tạo video.") unless scene_prompts_approved?
    return step_fail!("MPT chỉ nhận một thời lượng chung cho các cảnh.") unless one_scene_duration?
    return step_fail!("Model hoặc resolution không khớp cấu hình MPT.") unless profile_matches?
    return step_fail!("Thiếu chủ đề, ngôn ngữ hoặc kịch bản.") unless required_inputs_present?
    return step_fail!("Project video không tồn tại.") unless @video_project&.persisted?

    true
  end

  def step_prepare_submission
    build_video_request
    AiGeneration.transaction do
      @ai_generation = @video_project.ai_generations.create!(
        correlation_id: SecureRandom.uuid,
        status: :submitting,
        input_snapshot: @inputs,
        estimate_snapshot: @estimate,
        consent_snapshot: consent_snapshot
      )
      @workflow_run = @ai_generation.create_workflow_run!(
        operation_id: "ai-generation-#{@ai_generation.id}-mpt-video",
        operation: "ai_video_generation",
        stage: SUBMISSION_STAGE,
        status: :queued,
        checkpoint: { "correlation_id" => @ai_generation.correlation_id }
      )
    end
    true
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  def step_claim_submission
    claim_service = WorkflowRuns::ClaimService.new(
      workflow_run_id: @workflow_run.id,
      worker_id: worker_id,
      lease_duration: request_timeout + 30.seconds
    )
    return step_fail!(claim_service.errors.full_messages.to_sentence) unless claim_service.call

    @workflow_run = claim_service.workflow_run
    @fencing_token = claim_service.fencing_token
    true
  end

  def step_start_outbound_attempt
    start_service = OutboundAttempts::StartService.new(
      workflow_run_id: @workflow_run.id,
      worker_id: worker_id,
      fencing_token: @fencing_token,
      stage: SUBMISSION_STAGE,
      request_timeout_at: Time.current + request_timeout,
      idempotency_key: "ai-generation-#{@ai_generation.id}-mpt-video"
    )
    return step_fail!(start_service.errors.full_messages.to_sentence) unless start_service.call

    @outbound_attempt = start_service.outbound_attempt
    true
  end

  def step_submit_video
    response = Mpt::Client.new.create_video(payload: video_request, task_id: @ai_generation.correlation_id)
    return step_mark_and_reconcile("invalid_response") if response["task_id"].blank?

    step_confirm_submission(response["task_id"], provider_state: response["state"])
  rescue Mpt::Client::Error => error
    return step_mark_and_reconcile(error.code) if ambiguous_provider_error?(error.code)

    step_mark_submission_failed(error.code)
  end

  def step_mark_and_reconcile(error_code)
    step_mark_outcome_unknown(error_code)
    step_reconcile_task
  end

  def step_mark_outcome_unknown(error_code)
    AiGeneration.transaction do
      @outbound_attempt.update!(
        status: :outcome_unknown,
        sender_stopped_at: Time.current,
        safe_error_code: error_code
      )
      @ai_generation.update!(status: :outcome_unknown, safe_error_code: error_code)
      @workflow_run.update!(status: :reconciliation_required, worker_id: nil, lease_expires_at: nil)
      @workflow_run.workflow_audit_events.create!(
        outbound_attempt: @outbound_attempt,
        event_type: "mpt_video_submission_outcome_unknown",
        stage: SUBMISSION_STAGE,
        details: { safe_error_code: error_code }
      )
    end
    true
  end

  def step_recover_submission
    return false unless step_load_saved_submission
    if ai_generation.task_id.present?
      return step_existing_task_found if outbound_attempt.confirmed?

      return step_fail!("Task MPT đã lưu nhưng outbound attempt chưa được xác nhận.")
    end
    return step_fail!("Outbound attempt chưa ở trạng thái cần đối soát.") unless outbound_attempt.outcome_unknown?

    step_reconcile_task
  end

  def step_load_saved_submission
    @ai_generation = AiGeneration.find_by(id: @ai_generation_id)
    return step_fail!("Không tìm thấy AI generation cần đối soát.") unless @ai_generation

    @workflow_run = @ai_generation.workflow_run
    return step_fail!("Không tìm thấy workflow cần đối soát.") unless @workflow_run

    @outbound_attempt = @workflow_run.outbound_attempts.find_by(stage: SUBMISSION_STAGE)
    return step_fail!("Không tìm thấy outbound attempt cần đối soát.") unless @outbound_attempt

    true
  end

  def step_existing_task_found
    @task_id = ai_generation.task_id
    step_succeed!
    success?
  end

  def step_reconcile_task
    return false unless step_claim_reconciliation

    task = step_find_task_by_correlation_id
    return step_confirm_submission(task["task_id"], provider_state: task["state"]) if task

    step_release_reconciliation
    step_fail!("MPT chưa xác nhận được kết quả gửi video; cần tiếp tục đối soát.")
  end

  def step_claim_reconciliation
    claim_service = WorkflowRuns::ClaimService.new(
      workflow_run_id: @workflow_run.id,
      worker_id: worker_id
    )
    return step_fail!(claim_service.errors.full_messages.to_sentence) unless claim_service.call

    @workflow_run = claim_service.workflow_run
    @fencing_token = claim_service.fencing_token
    true
  end

  def step_find_task_by_correlation_id
    page = 1
    page_size = CONFIGURATION.fetch(:task_list_page_size).to_i
    return if page_size <= 0

    loop do
      task_page = Mpt::Client.new.tasks(page:, page_size:)
      tasks = task_page["tasks"]
      total = Integer(task_page.fetch("total"))
      return unless tasks.is_a?(Array) && total >= 0

      matching_task = tasks.find do |task|
        task.is_a?(Hash) && task["request_id"] == ai_generation.correlation_id
      end
      return matching_task if matching_task && matching_task["task_id"].present?
      return if page * page_size >= total || tasks.empty?

      page += 1
    end
  rescue Mpt::Client::Error, KeyError, ArgumentError, TypeError
    nil
  end

  def step_confirm_submission(task_id, provider_state: nil)
    @task_id = task_id.to_s
    AiGeneration.transaction do
      @outbound_attempt.update!(
        status: :confirmed,
        sender_stopped_at: Time.current,
        provider_reference: { provider: "money_printer_turbo", task_id: @task_id }
      )
      @ai_generation.update!(
        status: :processing,
        task_id: @task_id,
        provider_state: provider_state,
        safe_error_code: nil
      )
      @workflow_run.update!(status: :completed, worker_id: nil, lease_expires_at: nil)
      @workflow_run.workflow_audit_events.create!(
        outbound_attempt: @outbound_attempt,
        event_type: "mpt_video_submitted",
        stage: SUBMISSION_STAGE,
        details: { task_id: @task_id }
      )
    end
    step_succeed!
    success?
  end

  def step_mark_submission_failed(error_code)
    AiGeneration.transaction do
      @outbound_attempt.update!(
        status: :failed,
        sender_stopped_at: Time.current,
        safe_error_code: error_code
      )
      @ai_generation.update!(status: :failed, safe_error_code: error_code)
      @workflow_run.update!(status: :failed, worker_id: nil, lease_expires_at: nil)
      @workflow_run.workflow_audit_events.create!(
        outbound_attempt: @outbound_attempt,
        event_type: "mpt_video_submission_failed",
        stage: SUBMISSION_STAGE,
        details: { safe_error_code: error_code }
      )
    end
    step_fail!(error_code)
  end

  def step_release_reconciliation
    @workflow_run.update!(status: :reconciliation_required, worker_id: nil, lease_expires_at: nil)
  end

  def consent_snapshot
    {
      confirmed: true,
      confirmed_at: Time.current.iso8601,
      amount: @estimate.fetch(:total_amount).to_s,
      currency: @estimate.fetch(:currency),
      estimate: @estimate
    }
  end

  def build_video_request
    @video_request = {
      video_subject: @inputs.fetch(:video_subject),
      video_script: @inputs.fetch(:video_script),
      video_terms: @inputs.fetch(:scenes).map { |scene| scene.fetch(:prompt) },
      video_aspect: PROFILE.fetch(:video_aspect),
      video_clip_duration: @inputs.fetch(:scenes).first.fetch(:duration),
      video_count: PROFILE.fetch(:video_count),
      video_source: PROFILE.fetch(:video_source),
      video_language: @inputs.fetch(:language),
      voice_name: configured_voice_name,
      subtitle_enabled: true,
      match_materials_to_script: true
    }
  end

  def scene_prompts_approved?
    scenes = @inputs[:scenes]
    scenes.is_a?(Array) &&
      scenes.present? &&
      scenes.all? do |scene|
        scene.is_a?(Hash) && scene[:approved] == true && scene[:prompt].present?
      end
  end

  def one_scene_duration?
    scenes = @inputs[:scenes]
    return false unless scenes.is_a?(Array) && scenes.present?

    durations = scenes.map { |scene| scene[:duration] }
    return false unless durations.all? { |duration| duration.is_a?(Integer) }

    duration = durations.first
    duration.between?(PROFILE.fetch(:min_scene_duration), PROFILE.fetch(:max_scene_duration)) &&
      durations.uniq.one?
  end

  def profile_matches?
    @inputs[:model_id] == PROFILE.fetch(:model_id) &&
      @inputs[:resolution] == PROFILE.fetch(:resolution)
  end

  def required_inputs_present?
    @inputs[:video_subject].present? &&
      @inputs[:language].present? &&
      @inputs[:video_script].present?
  end

  def configured_voice_name
    tts_configuration = CONFIGURATION.fetch(:tts)
    "#{tts_configuration.fetch(:provider)}:#{tts_configuration.fetch(:voice_name)}"
  end

  def money_amount(amount)
    return if amount.nil? || amount.to_s.strip.empty?

    value = BigDecimal(amount.to_s)
    value if value >= 0
  rescue ArgumentError
    nil
  end

  def request_timeout
    CONFIGURATION.fetch(:open_timeout_seconds).to_i.seconds +
      CONFIGURATION.fetch(:read_timeout_seconds).to_i.seconds
  end

  def worker_id
    @worker_id ||= "mpt-submit-#{SecureRandom.uuid}"
  end

  def ambiguous_provider_error?(error_code)
    error_code == "network_request_failed" || error_code.start_with?("http_5")
  end
end
