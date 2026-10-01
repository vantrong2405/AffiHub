# frozen_string_literal: true

module Renderable
  extend ActiveSupport::Concern

  def render_json(object, options = {})
    if paginated?(object)
      render json: object,
            meta: pagination_meta(object),
            each_serializer: options.delete(:serializer),
            **options
    else
      render json: object, **options
    end
  end

  def render_error(error, status = nil)
    render json: error,
          serializer: ErrorSerializer,
          status: status || error.try(:status) || :unprocessable_entity
  end

  def render_collection(collection:, serializer: nil, meta: nil, status: :ok, **options)
    options[:each_serializer] = serializer if serializer
    options[:meta] = meta if meta.present?

    render json: collection, status: status, **options
  end

  def render_resource(resource:, serializer: nil, status: :ok, **options)
    options[:serializer] = serializer if serializer

    render json: resource, status: status, **options
  end

  private

  def paginated?(object)
    object.respond_to?(:current_page) &&
      object.respond_to?(:total_pages) &&
      object.respond_to?(:size)
  end

  def pagination_meta(collection)
    return nil unless collection.respond_to?(:current_page)

    {
      current_page: collection.current_page,
      total_pages: collection.total_pages,
      total_count: collection.total_count
    }
  end
end
