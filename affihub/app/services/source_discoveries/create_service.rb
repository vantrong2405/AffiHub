class SourceDiscoveries::CreateService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:youtube).deep_symbolize_keys
  DISCOVERY_CONFIGURATION = CONFIGURATION.fetch(:discovery)
  SEARCH_TYPES = DISCOVERY_CONFIGURATION.fetch(:search_types).values.map(&:to_s).freeze

  # @return [VideoProject] the project that owns the search
  attr_reader :video_project

  # @return [SourceDiscovery] the persisted search and its result list
  attr_reader :source_discovery

  # @return [Hash] configured YouTube regions and their Vietnamese labels
  attr_reader :regions

  # @return [Hash] configured YouTube categories and their Vietnamese labels
  attr_reader :video_categories

  # @return [String] the default region for keyword search
  attr_reader :default_region_code

  # Initializes a request to search YouTube video metadata.
  #
  # @param video_project_id [Integer] the project that owns the search
  # @param search_type [String] keyword or regional popular chart search
  # @param search_query [String, nil] keyword query for the keyword search type
  # @param region_code [String, nil] selected region for a popular chart
  # @param video_category_id [String, nil] optional category for a popular chart
  # @return [SourceDiscoveries::CreateService] the configured service
  def initialize(video_project_id:, search_type:, search_query:, region_code:, video_category_id:)
    @video_project_id = video_project_id
    @search_type = search_type.to_s
    @search_query = search_query.to_s.strip
    @region_code = region_code.to_s
    @video_category_id = video_category_id.to_s
    @regions = DISCOVERY_CONFIGURATION.fetch(:regions)
    @video_categories = DISCOVERY_CONFIGURATION.fetch(:video_categories)
    @default_region_code = CONFIGURATION.fetch(:default_region_code).to_s
    @source_discovery = SourceDiscovery.new(
      search_type: @search_type,
      search_query: @search_query,
      region_code: @region_code,
      video_category_id: @video_category_id
    )
    super()
  end

  # Searches YouTube and persists the result metadata for the project.
  #
  # @return [Boolean] whether the search completed and was persisted
  def call
    step_load_video_project
    return false unless step_validate_search
    return false unless step_fetch_results
    return false unless step_persist_results

    step_succeed!
    success?
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find(@video_project_id)
  end

  def step_validate_search
    return step_fail!("Hãy chọn một cách tìm kiếm video hợp lệ.") unless SEARCH_TYPES.include?(@search_type)

    if @search_type == step_keyword_search_type
      return step_fail!("Hãy nhập từ khóa cần tìm.") if @search_query.blank?
      return step_fail!("Từ khóa tìm kiếm quá dài.") if @search_query.length > DISCOVERY_CONFIGURATION.fetch(:max_query_characters)

      @region_code = @default_region_code
      @video_category_id = nil
    else
      return step_fail!("Hãy chọn khu vực được hỗ trợ.") unless step_supported_region?
      return step_fail!("Danh mục video không được hỗ trợ.") if @video_category_id.present? && !step_supported_category?

      @search_query = nil
      @video_category_id = nil if @video_category_id.blank?
    end

    @source_discovery.assign_attributes(
      search_query: @search_query,
      region_code: @region_code,
      video_category_id: @video_category_id
    )
    true
  end

  def step_fetch_results
    @searched_at = Time.current
    @search_results = if @search_type == step_keyword_search_type
      Youtube::DiscoveryClient.new.search_videos(query: @search_query)
    else
      Youtube::DiscoveryClient.new.popular_videos(
        region_code: @region_code,
        video_category_id: @video_category_id
      )
    end
    true
  rescue Youtube::DiscoveryClient::Error => error
    step_fail!(step_error_message(error.code))
  end

  def step_persist_results
    ApplicationRecord.transaction do
      @source_discovery.video_project = video_project
      @source_discovery.searched_at = @searched_at
      @source_discovery.save!
      step_unique_results.each_with_index do |attributes, position|
        metadata = YoutubeDiscoveryMetadata.find_or_initialize_by(video_id: attributes.fetch(:video_id))
        metadata.assign_attributes(step_metadata_attributes(attributes))
        metadata.save!
        @source_discovery.source_discovery_results.create!(youtube_discovery_metadata: metadata, position:)
      end
    end
    true
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  def step_unique_results
    @search_results.uniq { |attributes| attributes.fetch(:video_id) }
  end

  def step_metadata_attributes(attributes)
    {
      title: attributes.fetch(:title),
      channel_title: attributes.fetch(:channel_title),
      thumbnail_url: attributes.fetch(:thumbnail_url),
      attribution_url: attributes.fetch(:attribution_url),
      discovery_type: @search_type,
      search_query: @search_query,
      region_code: @region_code,
      video_category_id: @video_category_id,
      fetched_at: @searched_at
    }
  end

  def step_supported_region?
    DISCOVERY_CONFIGURATION.fetch(:regions).keys.map(&:to_s).include?(@region_code)
  end

  def step_supported_category?
    DISCOVERY_CONFIGURATION.fetch(:video_categories).keys.map(&:to_s).include?(@video_category_id)
  end

  def step_keyword_search_type
    DISCOVERY_CONFIGURATION.fetch(:search_types).fetch(:keyword).to_s
  end

  def step_error_message(code)
    case code
    when "quota_exhausted"
      "Quota tìm kiếm YouTube đã hết. Bạn vẫn có thể nhập URL video cụ thể hoặc chọn file MP4/MOV."
    when "rate_limited"
      "YouTube đang giới hạn yêu cầu tìm kiếm. Hãy thử lại sau hoặc nhập URL video cụ thể."
    else
      "Chưa thể tìm video trên YouTube. Hãy thử lại sau hoặc nhập URL video cụ thể."
    end
  end
end
