# frozen_string_literal: true

class DataSyncService < BaseService
  PAGE_VISIT_SCHEMA = {
    type: 'object',
    required: %w[id url title visited_at],
    properties: {
      id: { type: 'string' },
      url: { type: 'string', format: 'uri' },
      title: { type: 'string' },
      visited_at: { type: 'string', format: 'date-time' },
      source_page_visit_id: { type: %w[string null] }
    }
  }.freeze

  TAB_AGGREGATE_SCHEMA = {
    type: 'object',
    required: %w[id page_visit_id total_time_seconds active_time_seconds closed_at],
    properties: {
      id: { type: 'string' },
      page_visit_id: { type: 'string' },
      total_time_seconds: { type: 'integer', minimum: 0 },
      active_time_seconds: { type: 'integer', minimum: 0 },
      scroll_depth_percent: { type: 'integer', minimum: 0, maximum: 100 },
      closed_at: { type: 'string', format: 'date-time' }
    }
  }.freeze

  class << self
    def sync(user:, page_visits: [], tab_aggregates: [])
      new(user:, page_visits:, tab_aggregates:).sync
    end
  end

  def initialize(user:, page_visits: [], tab_aggregates: [])
    super()
    @user = user
    @raw_page_visits = Array(page_visits)
    @raw_tab_aggregates = Array(tab_aggregates)
    @page_visits = transform_page_visits(@raw_page_visits)
    @tab_aggregates = transform_tab_aggregates(@raw_tab_aggregates, @raw_page_visits)
  end

  def sync
    return invalid_params_result if user.blank?
    return validation_result unless validate_payload

    save_batch
    success_result(
      data: sync_stats,
      message: 'Data synced successfully'
    )
  rescue StandardError => e
    log_error('Data sync failed', e)
    failure_result(message: 'Data sync failed')
  end

  private

  attr_reader :user, :page_visits, :tab_aggregates, :raw_page_visits, :raw_tab_aggregates

  # Transform extension format to our internal format
  def transform_page_visits(visits)
    visits.map do |visit|
      {
        'id' => visit['id'] || visit['visitId'],
        'url' => visit['url'],
        'title' => visit['title'] || extract_title_from_url(visit['url']),
        'visited_at' => timestamp_to_iso8601(visit['visited_at'] || visit['startedAt']),
        'source_page_visit_id' => visit['source_page_visit_id'] || visit['sourcePageVisitId'],
        'tab_id' => visit['tabId'],
        'domain' => visit['domain'],
        'duration_seconds' => visit['durationSeconds'] || visit['duration_seconds'],
        'active_duration_seconds' => (visit['activeDuration'] || 0) / 1000, # Convert ms to seconds
        'engagement_rate' => visit['engagementRate'] || visit['engagement_rate'],
        'idle_periods' => visit['idlePeriods'] || visit['idle_periods'],
        'last_heartbeat' => visit['lastHeartbeat'] || visit['last_heartbeat'],
        'anonymous_client_id' => visit['anonymousClientId'] || visit['anonymous_client_id']
      }
    end
  end

  def transform_tab_aggregates(aggregates, page_visits)
    # Build a map of tabId -> first page visit ID for that tab
    tab_to_page_visit = {}
    page_visits.each do |visit|
      tab_id = visit['tabId']
      visit_id = visit['id'] || visit['visitId']
      next unless tab_id && visit_id

      # Keep the first (earliest) page visit for each tab
      tab_to_page_visit[tab_id] ||= visit_id
    end

    aggregates.map do |aggregate|
      # Handle browser extension format
      if aggregate['tabId'] && aggregate['startTime']
        # Browser extension format
        tab_id = aggregate['tabId']
        start_time = aggregate['startTime']
        last_active = aggregate['lastActiveTime'] || start_time

        # Find the actual page visit ID for this tab
        page_visit_id = tab_to_page_visit[tab_id]
        unless page_visit_id
          Rails.logger.warn "Skipping tab aggregate for tabId #{tab_id}: no matching page visit found"
          next nil
        end

        # Calculate actual duration from timestamps (more reliable than totalActiveDuration)
        calculated_duration_ms = last_active - start_time
        calculated_seconds = (calculated_duration_ms / 1000.0).to_i

        # Sanity check: Max 1 year (browsers shouldn't keep tabs for longer)
        # This catches corrupt data while allowing long-running tabs
        max_seconds = 365 * 24 * 3600 # 1 year

        if calculated_seconds > max_seconds || calculated_seconds < 0
          Rails.logger.warn "Skipping tab aggregate with invalid duration: #{calculated_seconds}s (#{calculated_seconds / 86400.0} days) for tabId #{tab_id}"
          next nil
        end

        # Generate ID from tabId and startTime
        id = aggregate['id'] || "agg_#{start_time}_#{tab_id}"

        # Validate page_count (max bigint is ~9.2 quintillion)
        page_count = aggregate['pageCount'] || aggregate['page_count']
        max_bigint = 9_223_372_036_854_775_807
        if page_count && page_count.to_i > max_bigint
          Rails.logger.warn "Capping invalid page_count #{page_count} to nil for tabId #{tab_id}"
          page_count = nil
        end

        {
          'id' => id,
          'page_visit_id' => page_visit_id,
          'total_time_seconds' => calculated_seconds,
          'active_time_seconds' => calculated_seconds,
          'scroll_depth_percent' => aggregate['scroll_depth_percent'] || 0,
          'closed_at' => timestamp_to_iso8601(last_active),
          'domain_durations' => aggregate['domainDurations'] || aggregate['domain_durations'],
          'page_count' => page_count,
          'current_url' => aggregate['currentUrl'] || aggregate['current_url'],
          'current_domain' => aggregate['currentDomain'] || aggregate['current_domain'],
          'statistics' => aggregate['statistics']
        }
      else
        # API format (already correct)
        {
          'id' => aggregate['id'],
          'page_visit_id' => aggregate['page_visit_id'] || aggregate['pageVisitId'],
          'total_time_seconds' => aggregate['total_time_seconds'] || aggregate['totalTimeSeconds'],
          'active_time_seconds' => aggregate['active_time_seconds'] || aggregate['activeTimeSeconds'],
          'scroll_depth_percent' => aggregate['scroll_depth_percent'] || aggregate['scrollDepthPercent'],
          'closed_at' => timestamp_to_iso8601(aggregate['closed_at'] || aggregate['closedAt'])
        }
      end.compact
    end.compact # Remove nil values from skipped aggregates
  end

  def extract_title_from_url(url)
    return 'Unknown' if url.blank?

    # Handle special URLs
    return 'Firefox Debugging' if url.start_with?('about:')
    return 'New Tab' if url == 'about:newtab'

    # Extract domain as fallback title
    uri = URI.parse(url)
    uri.host&.gsub('www.', '')&.capitalize || 'Unknown'
  rescue URI::InvalidURIError
    'Unknown'
  end

  def timestamp_to_iso8601(value)
    return value if value.blank?
    return value if value.is_a?(String) && value.match?(/^\d{4}-\d{2}-\d{2}/)

    # Convert millisecond timestamp to ISO8601
    Time.at(value.to_i / 1000.0).utc.iso8601
  rescue StandardError
    nil
  end

  def validate_payload
    @validation_errors = []

    page_visits.each_with_index do |visit, index|
      validate_record(visit, PAGE_VISIT_SCHEMA, "pageVisits[#{index}]")
    end

    tab_aggregates.each_with_index do |aggregate, index|
      validate_record(aggregate, TAB_AGGREGATE_SCHEMA, "tabAggregates[#{index}]")
    end

    @validation_errors.empty?
  end

  def validate_record(record, schema, path)
    schemer = JSONSchemer.schema(schema)
    errors = schemer.validate(record).to_a

    errors.each do |error|
      @validation_errors << {
        path:,
        field: error['data_pointer'],
        error: error['error']
      }
    end
  end

  def save_batch
    ActiveRecord::Base.transaction do
      save_page_visits if page_visits.any?
      save_tab_aggregates if tab_aggregates.any?
    end
  end

  def save_page_visits
    # Deduplicate by ID, keeping the latest version (highest endedAt/timestamp)
    deduplicated_visits = page_visits
                          .group_by { |v| v['id'] }
                          .map do |_id, versions|
      versions.max_by { |v| v['visited_at'] || v['timestamp'] || 0 }
    end

    visits_params = deduplicated_visits.map do |visit|
      {
        id: visit['id'],
        user_id: user.id,
        url: visit['url'],
        title: visit['title'],
        visited_at: visit['visited_at'],
        source_page_visit_id: visit['source_page_visit_id'],
        tab_id: visit['tab_id'],
        domain: visit['domain'],
        duration_seconds: visit['duration_seconds'],
        active_duration_seconds: visit['active_duration_seconds'],
        engagement_rate: visit['engagement_rate'],
        idle_periods: visit['idle_periods'],
        last_heartbeat: visit['last_heartbeat'],
        anonymous_client_id: visit['anonymous_client_id']
      }
    end

    PageVisit.upsert_all(visits_params, unique_by: :id)
  end

  def save_tab_aggregates
    return if tab_aggregates.empty?

    # Deduplicate by ID, keeping the latest version
    deduplicated_aggregates = tab_aggregates
                               .group_by { |a| a['id'] }
                               .map do |_id, versions|
      versions.max_by { |a| a['closed_at'] || 0 }
    end

    aggregates_params = deduplicated_aggregates.map do |aggregate|
      {
        id: aggregate['id'],
        page_visit_id: aggregate['page_visit_id'],
        total_time_seconds: aggregate['total_time_seconds'],
        active_time_seconds: aggregate['active_time_seconds'],
        scroll_depth_percent: aggregate['scroll_depth_percent'],
        closed_at: aggregate['closed_at'],
        domain_durations: aggregate['domain_durations'],
        page_count: aggregate['page_count'],
        current_url: aggregate['current_url'],
        current_domain: aggregate['current_domain'],
        statistics: aggregate['statistics']
      }
    end

    TabAggregate.upsert_all(aggregates_params, unique_by: :id)
  end

  def sync_stats
    {
      page_visits_synced: page_visits.size,
      tab_aggregates_synced: tab_aggregates.size
    }
  end

  def invalid_params_result
    failure_result(message: 'User is required')
  end

  def validation_result
    failure_result(
      message: 'Validation failed for one or more records',
      errors: @validation_errors
    )
  end
end
