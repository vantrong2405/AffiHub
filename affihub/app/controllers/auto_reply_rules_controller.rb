class AutoReplyRulesController < MainController
  # Loads all auto-reply rules for the workspace.
  #
  # @return [ActionController::Metal::Response] the auto-reply rule list response
  def index
    service = AutoReplyRules::IndexService.new(social_destination_id: params[:social_destination_id])
    service.call
    @auto_reply_rules = service.rules
  end

  # Loads one saved auto-reply rule.
  #
  # @return [ActionController::Metal::Response] the auto-reply rule detail response
  def show
    service = AutoReplyRules::ShowService.new(rule_id: params[:id])
    return head :not_found unless service.call

    @auto_reply_rule = service.rule
  end

  # Builds a rule form with currently connected comment destinations.
  #
  # @return [ActionController::Metal::Response] the new rule form response
  def new
    load_new_rule_form
  end

  # Creates one fixed default or keyword response rule.
  #
  # @return [ActionController::Metal::Response] the auto-reply rule create response
  def create
    service = AutoReplyRules::CreateService.new(
      social_destination_id: rule_params[:social_destination_id],
      attributes: rule_params.except(:social_destination_id)
    )
    service.call
    @auto_reply_rule = service.rule
    load_new_rule_form(rule: service.rule) unless service.success?

    render_service(service, failure: :new, notice: "Đã tạo quy tắc tự trả lời.") do
      auto_reply_rule_path(service.rule)
    end
  end

  # Loads a saved rule into its edit form.
  #
  # @return [ActionController::Metal::Response] the edit rule form response
  def edit
    service = AutoReplyRules::ShowService.new(rule_id: params[:id])
    return head :not_found unless service.call

    @auto_reply_rule = service.rule
  end

  # Updates one rule without moving it to another destination.
  #
  # @return [ActionController::Metal::Response] the auto-reply rule update response
  def update
    service = AutoReplyRules::UpdateService.new(rule_id: params[:id], attributes: rule_update_params)
    service.call
    return head :not_found unless service.rule

    @auto_reply_rule = service.rule

    render_service(service, failure: :edit, notice: "Đã cập nhật quy tắc tự trả lời.") do
      auto_reply_rule_path(service.rule)
    end
  end

  # Deletes one saved rule and updates its Meta webhook subscription if needed.
  #
  # @return [ActionController::Metal::Response] the auto-reply rule deletion response
  def destroy
    service = AutoReplyRules::DestroyService.new(rule_id: params[:id])
    service.call
    return head :not_found unless service.rule

    render_service(
      service,
      success: auto_reply_rules_path,
      failure_redirect: auto_reply_rules_path,
      notice: "Đã xóa quy tắc tự trả lời.",
      alert: "Không thể xóa quy tắc tự trả lời."
    )
  end

  private

  def load_new_rule_form(rule: nil)
    service = AutoReplyRules::NewService.new(rule:)
    service.call
    @auto_reply_rule = service.rule
    @social_destinations = service.destinations
  end

  def rule_params
    params.require(:auto_reply_rule).permit(
      :social_destination_id,
      :rule_type,
      :keyword,
      :reply_text,
      :enabled
    )
  end

  def rule_update_params
    rule_params.except(:social_destination_id)
  end
end
