# frozen_string_literal: true

class AiGenerationsController < MainController
  before_action :load_ai_generation_page, only: %i[edit show]

  # Loads the topic and generation settings form for one project.
  #
  # @return [ActionController::Metal::Response] the new generation response
  def new
    service = AiGenerations::NewService.new(video_project_id: params[:video_project_id])
    service.call
    @video_project = service.video_project
    @create_form = service.create_form
  end

  # Generates and saves a draft script for review.
  #
  # @return [ActionController::Metal::Response] the draft creation response
  def create
    service = AiGenerations::CreateDraftService.new(
      video_project_id: params[:video_project_id],
      inputs: ai_generation_params
    )
    service.call
    @video_project = service.video_project
    raise ActiveRecord::RecordNotFound unless @video_project

    @create_form = service.input_form || AiGenerations::CreateForm.new(ai_generation_params)
    render_service(service, failure: :new, notice: "Đã tạo kịch bản nháp.") do
      edit_video_project_ai_generation_path(service.video_project, service.ai_generation)
    end
  end

  # Applies the requested script approval or scene estimate step.
  #
  # @return [ActionController::Metal::Response] the generation update response
  def update
    update_params = ai_generation_update_params
    service = update_service(update_params)
    service.call
    @video_project = service.video_project
    @ai_generation = service.ai_generation
    @outbound_attempt = service.outbound_attempt if %w[submit resolve_outcome].include?(update_params[:step])
    @video_script = update_params[:video_script]
    @script_approved = update_params[:script_approved]
    @scene_inputs = update_params[:scenes]

    failure_view = update_params[:step] == "resolve_outcome" ? :show : :edit
    render_service(service, failure: failure_view, notice: update_notice(update_params)) do
      if %w[submit resolve_outcome].include?(update_params[:step])
        video_project_ai_generation_path(service.video_project, service.ai_generation)
      else
        edit_video_project_ai_generation_path(service.video_project, service.ai_generation)
      end
    end
  end

  # Loads the current AI generation step for editing and approval.
  #
  # @return [ActionController::Metal::Response] the generation workflow response
  def edit
    @editing_script = @ai_generation.script_ready? || params[:step] == "script"
  end

  # Loads the current AI generation status and output summary.
  #
  # @return [ActionController::Metal::Response] the generation status response
  def show; end

  private

  # Loads the nested generation through the application service.
  def load_ai_generation_page
    service = AiGenerations::ShowService.new(
      video_project_id: params[:video_project_id],
      ai_generation_id: params[:id]
    )
    service.call
    @video_project = service.video_project
    @ai_generation = service.ai_generation
    @outbound_attempt = service.outbound_attempt
  end

  def ai_generation_params
    params.require(:ai_generation).permit(:topic, :language, :tone, :target_duration)
  end

  def ai_generation_update_params
    params.require(:ai_generation).permit(
      :step,
      :video_script,
      :script_approved,
      :budget,
      :confirmed,
      :decision,
      :evidence,
      :provider_reference,
      :risk_confirmed,
      scenes: [ :prompt, :duration, :approved ]
    )
  end

  # Builds the Service for the submitted workflow step.
  def update_service(update_params)
    case update_params[:step]
    when "create_prompts"
      AiGenerations::CreatePromptsService.new(
        video_project_id: params[:video_project_id],
        ai_generation_id: params[:id],
        video_script: update_params[:video_script],
        script_approved: update_params[:script_approved]
      )
    when "create_estimate"
      AiGenerations::CreateEstimateService.new(
        video_project_id: params[:video_project_id],
        ai_generation_id: params[:id],
        scenes: update_params[:scenes]
      )
    when "submit"
      AiGenerations::SubmitService.new(
        video_project_id: params[:video_project_id],
        draft_generation_id: params[:id],
        budget: update_params[:budget],
        confirmed: ActiveModel::Type::Boolean.new.cast(update_params[:confirmed])
      )
    when "resolve_outcome"
      AiGenerations::ResolveOutcomeService.new(
        video_project_id: params[:video_project_id],
        ai_generation_id: params[:id],
        decision: update_params[:decision],
        evidence: update_params[:evidence],
        provider_reference: update_params[:provider_reference],
        risk_confirmed: ActiveModel::Type::Boolean.new.cast(update_params[:risk_confirmed])
      )
    else
      raise ActionController::BadRequest, "Invalid AI generation step"
    end
  end

  def update_notice(update_params)
    return "Đã lưu kịch bản và tạo gợi ý cảnh." if update_params[:step] == "create_prompts"
    return "Đã xác nhận ngân sách và gửi video AI." if update_params[:step] == "submit"
    return "Đã lưu quyết định đối soát và bằng chứng." if update_params[:step] == "resolve_outcome"

    "Đã lưu báo giá cho các gợi ý cảnh."
  end
end
