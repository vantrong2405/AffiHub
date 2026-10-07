# frozen_string_literal: true

class AiGenerations::CreateEstimateService < ApplicationService
  PROFILE = Rails.application.config_for(:money_printer_turbo)
    .deep_symbolize_keys
    .fetch(:generation_profile)

  attr_reader :video_project, :ai_generation, :cost_breakdown, :total_amount, :required_costs_known

  # Initializes a server-side estimate for the submitted scene prompts.
  #
  # @param video_project_id [Integer] the project that owns the generation
  # @param ai_generation_id [Integer] the generation receiving the estimate
  # @param scenes [Array<Hash>] the edited prompts, durations, and approvals
  # @return [AiGenerations::CreateEstimateService] the configured service
  def initialize(video_project_id:, ai_generation_id:, scenes:)
    @video_project_id = video_project_id
    @ai_generation_id = ai_generation_id
    @scene_inputs = scenes
    super()
  end

  # Saves scene edits, requests provider quotes, and stores the resulting estimate.
  #
  # @return [Boolean] whether the estimate snapshot was saved
  def call
    step_load_generation
    return false unless step_normalize_scenes
    return false unless step_save_scene_inputs
    return false unless step_validate_scene_approvals
    return false unless step_request_estimate
    return false unless step_save_estimate

    step_succeed!
    success?
  end

  private

  def step_load_generation
    @video_project = VideoProject.find(@video_project_id)
    @ai_generation = video_project.ai_generations.find(@ai_generation_id)
    @input_snapshot = ai_generation.input_snapshot.deep_symbolize_keys
  end

  def step_normalize_scenes
    return step_fail!("Danh sách cảnh không khớp với kịch bản.") unless scene_count_matches?

    @scenes = @scene_inputs.map do |scene_input|
      scene = scene_input.to_h.symbolize_keys
      {
        prompt: scene[:prompt].to_s.strip,
        duration: Integer(scene[:duration], exception: false),
        resolution: @input_snapshot.fetch(:resolution),
        aspect_ratio: PROFILE.fetch(:video_aspect),
        approved: ActiveModel::Type::Boolean.new.cast(scene[:approved])
      }
    end
    return step_fail!("Mỗi cảnh cần có mô tả.") unless scene_prompts_present?
    return step_fail!("Thời lượng cảnh phải trong khoảng 3–12 giây.") unless scene_durations_valid?
    return step_fail!("MPT yêu cầu thời lượng chung cho các cảnh.") unless scene_durations_match?

    true
  rescue ArgumentError, TypeError
    step_fail!("Thời lượng cảnh không hợp lệ.")
  end

  def step_save_scene_inputs
    @input_snapshot = @input_snapshot.merge(scenes: @scenes)
    ai_generation.update!(input_snapshot: @input_snapshot, estimate_snapshot: {}, status: :prompts_ready)
    true
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  def step_validate_scene_approvals
    return true if @scenes.all? { |scene| scene.fetch(:approved) }

    step_fail!("Cần duyệt tất cả gợi ý cảnh trước khi lấy báo giá.")
  end

  def step_request_estimate
    service = AiGenerationEstimates::CreateService.new(
      model_id: @input_snapshot.fetch(:model_id),
      scenes: @scenes,
      input_snapshot: @input_snapshot
    )
    return step_fail!(service.errors.full_messages.to_sentence) unless service.call

    @scene_estimates = service.scene_estimates
    @cost_breakdown = service.cost_breakdown
    @total_amount = service.total_amount
    @required_costs_known = service.required_costs_known
    true
  end

  def step_save_estimate
    estimate_snapshot = {
      input_snapshot: @input_snapshot,
      scene_estimates: @scene_estimates,
      cost_breakdown: @cost_breakdown,
      total_amount: @total_amount&.to_s("F"),
      currency: @cost_breakdown.dig(:unknown, :currency),
      required_costs_known: @required_costs_known,
      estimated_at: Time.current.iso8601
    }
    ai_generation.update!(estimate_snapshot: estimate_snapshot)
    true
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  def scene_count_matches?
    @scene_inputs.is_a?(Array) && @scene_inputs.length == @input_snapshot.fetch(:scene_count)
  end

  def scene_prompts_present?
    @scenes.all? { |scene| scene.fetch(:prompt).present? }
  end

  def scene_durations_valid?
    @scenes.all? do |scene|
      scene.fetch(:duration).present? &&
        scene.fetch(:duration).between?(PROFILE.fetch(:min_scene_duration), PROFILE.fetch(:max_scene_duration))
    end
  end

  def scene_durations_match?
    @scenes.map { |scene| scene.fetch(:duration) }.uniq.one?
  end
end
