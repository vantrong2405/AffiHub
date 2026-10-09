class RenderVersionsController < MainController
  # Lists render versions for one project.
  #
  # @return [ActionController::Metal::Response] the render history response
  def index
    service = RenderVersions::IndexService.new(video_project_id: params[:video_project_id])
    service.call
    @video_project = service.video_project
    @render_versions = service.render_versions
  end

  # Loads the editor for a ready source in the selected project.
  #
  # @return [ActionController::Metal::Response] the editor response
  def new
    load_editor_form
  end

  # Creates and queues an immutable render version.
  #
  # @return [ActionController::Metal::Response] the render create response
  def create
    load_editor_form
    @edit_config = build_edit_config
    service = RenderVersions::CreateService.new(
      video_project: @video_project,
      source_asset: @selected_source_asset,
      edit_config: @edit_config
    )
    service.call
    @render_version = service.render_version

    render_service(service, failure: :new, notice: "Đã tạo bản render. Worker đang xử lý.") do
      video_project_render_version_path(@video_project, service.render_version)
    end
  end

  # Shows the selected render and compares a requested source timecode.
  #
  # @return [ActionController::Metal::Response] the render detail response
  def show
    service = RenderVersions::ShowService.new(
      video_project_id: params[:video_project_id],
      render_version_id: params[:id]
    )
    service.call
    @video_project = service.video_project
    @render_version = service.render_version
    @source_asset = service.source_asset
    @social_destinations = service.social_destinations
    @frames = []
    response_status = :ok

    if params[:timecode].present?
      comparison_service = RenderVersions::CompareFramesService.new(
        render_version_id: @render_version.id,
        timecodes: [ parsed_timecode ]
      )
      if comparison_service.call
        @frames = comparison_service.frames
      else
        @comparison_error = comparison_service.errors.full_messages.to_sentence
        response_status = :unprocessable_content
      end
    end

    render :show, status: response_status
  end

  private

  def load_editor_form
    service = RenderVersions::NewService.new(
      video_project_id: params[:video_project_id],
      source_asset_id: params[:source_asset_id] || params.dig(:render_version, :source_asset_id)
    )
    service.call
    raise ActiveRecord::RecordNotFound if service.errors.any?

    @video_project = service.video_project
    @source_assets = service.source_assets
    @selected_source_asset = service.selected_source_asset
    @project_media_assets = service.project_media_assets
    @edit_config = service.edit_config
    @segment_forms = @edit_config.fetch("segments")
    @overlay_forms = [ {} ]
    @delogo_region_forms = [ {} ]
  end

  def build_edit_config
    form_values = render_version_params
    canvas_values = form_values.fetch(:canvas, ActionController::Parameters.new)
    background_values = canvas_values.fetch(:background, ActionController::Parameters.new)
    @segment_forms = Array(form_values[:segments]).map { |values| values.to_h.with_indifferent_access }
    @overlay_forms = Array(form_values[:overlays]).map { |values| values.to_h.with_indifferent_access }
    @delogo_region_forms = Array(form_values[:delogo_regions]).map { |values| values.to_h.with_indifferent_access }

    {
      "schema_version" => 1,
      "segments" => @segment_forms.map do |segment|
        {
          "start_seconds" => numeric_value(segment[:start_seconds]),
          "end_seconds" => numeric_value(segment[:end_seconds]),
          "speed" => numeric_value(segment[:speed]),
          "audio_mode" => segment[:audio_mode].to_s,
          "audio_volume" => numeric_value(segment[:audio_volume])
        }
      end,
      "canvas" => {
        "mode" => canvas_values[:mode].to_s,
        "background" => build_background(background_values)
      },
      "filters" => {
        "brightness" => numeric_value(form_values.dig(:filters, :brightness)),
        "contrast" => numeric_value(form_values.dig(:filters, :contrast))
      },
      "overlays" => build_overlays(@overlay_forms),
      "delogo_regions" => build_delogo_regions(@delogo_region_forms)
    }
  end

  def render_version_params
    params.require(:render_version).permit(
      :source_asset_id,
      { segments: %i[start_seconds end_seconds speed audio_mode audio_volume] },
      { canvas: [ :mode, { background: %i[type color project_media_asset_id source_asset_id] } ] },
      { filters: %i[brightness contrast] },
      { overlays: %i[type text output_start_seconds output_end_seconds x y width height opacity project_media_asset_id] },
      { delogo_regions: %i[x y width height] }
    )
  end

  def build_background(background_values)
    background_type = background_values[:type].to_s

    case background_type
    when "blur"
      { "type" => background_type }
    when "color"
      { "type" => background_type, "color" => background_values[:color].to_s }
    when "image"
      { "type" => background_type, "project_media_asset_id" => integer_value(background_values[:project_media_asset_id]) }
    when "video"
      { "type" => background_type, "source_asset_id" => integer_value(background_values[:source_asset_id]) }
    else
      { "type" => background_type }
    end
  end

  def build_overlays(overlay_values)
    Array(overlay_values).each_with_object([]) do |values, overlays|
      overlay_type = values[:type].to_s
      next if overlay_type.blank?

      overlay = {
        "type" => overlay_type,
        "output_start_seconds" => numeric_value(values[:output_start_seconds]),
        "output_end_seconds" => numeric_value(values[:output_end_seconds]),
        "x" => numeric_value(values[:x]),
        "y" => numeric_value(values[:y]),
        "width" => numeric_value(values[:width]),
        "height" => numeric_value(values[:height]),
        "opacity" => numeric_value(values[:opacity])
      }

      if %w[text subtitle].include?(overlay_type)
        overlay["text"] = values[:text].to_s
      elsif overlay_type == "logo"
        overlay["project_media_asset_id"] = integer_value(values[:project_media_asset_id])
      end

      overlays << overlay
    end
  end

  def build_delogo_regions(delogo_values)
    Array(delogo_values).each_with_object([]) do |values, regions|
      next if values.values.all?(&:blank?)

      regions << {
        "x" => integer_value(values[:x]),
        "y" => integer_value(values[:y]),
        "width" => integer_value(values[:width]),
        "height" => integer_value(values[:height])
      }
    end
  end

  def numeric_value(value)
    Float(value)
  rescue ArgumentError, TypeError
    value
  end

  def integer_value(value)
    Integer(value)
  rescue ArgumentError, TypeError
    value
  end

  def parsed_timecode
    numeric_value(params[:timecode])
  end
end
