# Phase 2.3: Basic Insights APIs

## Overview

**Goal:** Provide server-side aggregated insights to reduce client-side computation and bandwidth.

**Why Server-Side:**
- ✅ Faster (no need to fetch 10k records)
- ✅ Less bandwidth (fetch summary, not raw data)
- ✅ Better UX (instant insights)
- ✅ Validates data quality (if insights work, data is good)

---

## API Endpoints

### 1. Daily Summary

**Endpoint:** `GET /api/v1/insights/daily_summary`

**Query Parameters:**
- `date` (optional): Date in YYYY-MM-DD format (defaults to today)

**Response:**
```json
{
  "success": true,
  "data": {
    "date": "2025-10-18",
    "total_sites_visited": 42,
    "unique_domains": 15,
    "total_time_seconds": 14400,
    "active_time_seconds": 8640,
    "avg_engagement_rate": 0.62,
    "top_domain": {
      "domain": "github.com",
      "visits": 12,
      "time_seconds": 3600
    },
    "hourly_breakdown": [
      { "hour": 9, "visits": 5, "time_seconds": 1800 },
      { "hour": 10, "visits": 8, "time_seconds": 2400 },
      ...
    ]
  }
}
```

---

### 2. Weekly Summary

**Endpoint:** `GET /api/v1/insights/weekly_summary`

**Query Parameters:**
- `week` (optional): ISO week format "2025-W42" (defaults to current week)

**Response:**
```json
{
  "success": true,
  "data": {
    "week": "2025-W42",
    "start_date": "2025-10-14",
    "end_date": "2025-10-20",
    "total_sites_visited": 234,
    "unique_domains": 45,
    "total_time_seconds": 86400,
    "active_time_seconds": 51840,
    "avg_engagement_rate": 0.58,
    "daily_breakdown": [
      {
        "date": "2025-10-14",
        "visits": 45,
        "time_seconds": 12000
      },
      ...
    ],
    "top_domains": [
      { "domain": "github.com", "visits": 56, "time_seconds": 14400 },
      { "domain": "stackoverflow.com", "visits": 32, "time_seconds": 7200 },
      ...
    ]
  }
}
```

---

### 3. Top Sites

**Endpoint:** `GET /api/v1/insights/top_sites`

**Query Parameters:**
- `period` (optional): "day", "week", "month" (default: "week")
- `limit` (optional): Number of results (default: 10, max: 50)
- `sort_by` (optional): "visits" or "time" (default: "time")

**Response:**
```json
{
  "success": true,
  "data": {
    "period": "week",
    "start_date": "2025-10-12",
    "end_date": "2025-10-18",
    "sites": [
      {
        "domain": "github.com",
        "visits": 67,
        "total_time_seconds": 18000,
        "avg_engagement_rate": 0.75,
        "first_visit": "2025-10-12T09:30:00Z",
        "last_visit": "2025-10-18T16:45:00Z"
      },
      {
        "domain": "stackoverflow.com",
        "visits": 45,
        "total_time_seconds": 10800,
        "avg_engagement_rate": 0.62,
        "first_visit": "2025-10-13T10:15:00Z",
        "last_visit": "2025-10-18T14:20:00Z"
      },
      ...
    ]
  }
}
```

---

### 4. Recent Activity

**Endpoint:** `GET /api/v1/insights/recent_activity`

**Query Parameters:**
- `limit` (optional): Number of results (default: 20, max: 100)
- `since` (optional): ISO 8601 timestamp (only return activity after this time)

**Response:**
```json
{
  "success": true,
  "data": {
    "activities": [
      {
        "type": "browsing_session",
        "started_at": "2025-10-18T14:30:00Z",
        "ended_at": "2025-10-18T15:45:00Z",
        "duration_seconds": 4500,
        "domains": ["github.com", "docs.anthropic.com"],
        "visit_count": 8,
        "avg_engagement": 0.78
      },
      {
        "type": "quick_search",
        "started_at": "2025-10-18T13:15:00Z",
        "ended_at": "2025-10-18T13:20:00Z",
        "duration_seconds": 300,
        "domains": ["google.com", "stackoverflow.com"],
        "visit_count": 5,
        "avg_engagement": 0.45
      },
      ...
    ]
  }
}
```

---

### 5. Productivity Hours

**Endpoint:** `GET /api/v1/insights/productivity_hours`

**Query Parameters:**
- `period` (optional): "week", "month" (default: "week")

**Response:**
```json
{
  "success": true,
  "data": {
    "period": "week",
    "most_productive_hour": 14,
    "least_productive_hour": 12,
    "hourly_stats": [
      {
        "hour": 9,
        "avg_engagement": 0.65,
        "total_time_seconds": 3600,
        "visit_count": 15
      },
      {
        "hour": 10,
        "avg_engagement": 0.72,
        "total_time_seconds": 4200,
        "visit_count": 18
      },
      ...
    ],
    "day_of_week_stats": [
      {
        "day": "Monday",
        "avg_engagement": 0.68,
        "total_time_seconds": 18000
      },
      ...
    ]
  }
}
```

---

## Implementation

### Services

```ruby
# frozen_string_literal: true

# app/services/insights/daily_summary_service.rb
module Insights
  class DailySummaryService < BaseService
    def self.call(user:, date: Date.today)
      new(user: user, date: date).call
    end

    def initialize(user:, date: Date.today)
      super()
      @user = user
      @date = date.is_a?(String) ? Date.parse(date) : date
    end

    def call
      visits = fetch_visits

      success_result(
        data: {
          date: @date.to_s,
          total_sites_visited: visits.count,
          unique_domains: visits.distinct.count(:domain),
          total_time_seconds: visits.sum(:duration_seconds) || 0,
          active_time_seconds: visits.sum(:active_duration_seconds) || 0,
          avg_engagement_rate: visits.average(:engagement_rate)&.round(2) || 0.0,
          top_domain: calculate_top_domain(visits),
          hourly_breakdown: calculate_hourly_breakdown(visits)
        }
      )
    end

    private

    attr_reader :user, :date

    def fetch_visits
      user.page_visits
          .where('DATE(visited_at) = ?', date)
          .valid_data
    end

    def calculate_top_domain(visits)
      top = visits.group(:domain)
                  .select('domain, COUNT(*) as visit_count, SUM(duration_seconds) as total_time')
                  .order('total_time DESC')
                  .first

      return nil unless top

      {
        domain: top.domain,
        visits: top.visit_count,
        time_seconds: top.total_time || 0
      }
    end

    def calculate_hourly_breakdown(visits)
      visits.group("EXTRACT(HOUR FROM visited_at)")
            .select('EXTRACT(HOUR FROM visited_at) as hour, COUNT(*) as visit_count, SUM(duration_seconds) as total_time')
            .order('hour')
            .map do |row|
              {
                hour: row.hour.to_i,
                visits: row.visit_count,
                time_seconds: row.total_time || 0
              }
            end
    end
  end
end
```

```ruby
# frozen_string_literal: true

# app/services/insights/top_sites_service.rb
module Insights
  class TopSitesService < BaseService
    def self.call(user:, period: 'week', limit: 10, sort_by: 'time')
      new(user: user, period: period, limit: limit, sort_by: sort_by).call
    end

    def initialize(user:, period: 'week', limit: 10, sort_by: 'time')
      super()
      @user = user
      @period = period
      @limit = [[limit.to_i, 1].max, 50].min
      @sort_by = sort_by
    end

    def call
      date_range = calculate_date_range

      visits = user.page_visits
                   .where('visited_at >= ? AND visited_at <= ?', date_range[:start], date_range[:end])
                   .valid_data

      sites = calculate_top_sites(visits)

      success_result(
        data: {
          period: @period,
          start_date: date_range[:start].to_date.to_s,
          end_date: date_range[:end].to_date.to_s,
          sites: sites
        }
      )
    end

    private

    attr_reader :user, :period, :limit, :sort_by

    def calculate_date_range
      case period
      when 'day'
        { start: Time.current.beginning_of_day, end: Time.current.end_of_day }
      when 'week'
        { start: 7.days.ago.beginning_of_day, end: Time.current.end_of_day }
      when 'month'
        { start: 30.days.ago.beginning_of_day, end: Time.current.end_of_day }
      else
        { start: 7.days.ago.beginning_of_day, end: Time.current.end_of_day }
      end
    end

    def calculate_top_sites(visits)
      sort_column = sort_by == 'visits' ? 'visit_count' : 'total_time'

      visits.group(:domain)
            .select(
              'domain',
              'COUNT(*) as visit_count',
              'SUM(duration_seconds) as total_time',
              'AVG(engagement_rate) as avg_engagement',
              'MIN(visited_at) as first_visit',
              'MAX(visited_at) as last_visit'
            )
            .order("#{sort_column} DESC")
            .limit(limit)
            .map do |row|
              {
                domain: row.domain,
                visits: row.visit_count,
                total_time_seconds: row.total_time || 0,
                avg_engagement_rate: row.avg_engagement&.round(2) || 0.0,
                first_visit: row.first_visit.iso8601,
                last_visit: row.last_visit.iso8601
              }
            end
    end
  end
end
```

```ruby
# frozen_string_literal: true

# app/services/insights/recent_activity_service.rb
module Insights
  class RecentActivityService < BaseService
    SESSION_GAP_SECONDS = 600  # 10 minutes

    def self.call(user:, limit: 20, since: nil)
      new(user: user, limit: limit, since: since).call
    end

    def initialize(user:, limit: 20, since: nil)
      super()
      @user = user
      @limit = [[limit.to_i, 1].max, 100].min
      @since = since ? Time.zone.parse(since) : 24.hours.ago
    end

    def call
      visits = fetch_visits
      sessions = group_into_sessions(visits)

      success_result(
        data: {
          activities: sessions.take(limit)
        }
      )
    end

    private

    attr_reader :user, :limit, :since

    def fetch_visits
      user.page_visits
          .where('visited_at >= ?', since)
          .valid_data
          .order(visited_at: :desc)
    end

    def group_into_sessions(visits)
      sessions = []
      current_session = nil

      visits.each do |visit|
        if current_session.nil?
          current_session = start_session(visit)
        elsif time_gap(current_session[:ended_at], visit.visited_at) > SESSION_GAP_SECONDS
          # Gap too large, start new session
          sessions << finalize_session(current_session)
          current_session = start_session(visit)
        else
          # Continue current session
          add_to_session(current_session, visit)
        end
      end

      sessions << finalize_session(current_session) if current_session

      sessions
    end

    def start_session(visit)
      {
        started_at: visit.visited_at,
        ended_at: visit.visited_at,
        visits: [visit],
        domains: Set.new([visit.domain])
      }
    end

    def add_to_session(session, visit)
      session[:ended_at] = visit.visited_at if visit.visited_at < session[:ended_at]
      session[:visits] << visit
      session[:domains].add(visit.domain)
    end

    def finalize_session(session)
      duration = (session[:started_at] - session[:ended_at]).abs.to_i
      avg_engagement = session[:visits].map(&:engagement_rate).compact.sum / session[:visits].size.to_f

      {
        type: classify_session(duration, session[:visits].size),
        started_at: session[:ended_at].iso8601,  # Reversed because ordered desc
        ended_at: session[:started_at].iso8601,
        duration_seconds: duration,
        domains: session[:domains].to_a,
        visit_count: session[:visits].size,
        avg_engagement: avg_engagement.round(2)
      }
    end

    def classify_session(duration, visit_count)
      if duration > 1800 && visit_count > 10
        'research_session'
      elsif duration > 600
        'browsing_session'
      elsif visit_count > 5
        'quick_search'
      else
        'brief_visit'
      end
    end

    def time_gap(time1, time2)
      (time1 - time2).abs
    end
  end
end
```

```ruby
# frozen_string_literal: true

# app/services/insights/productivity_hours_service.rb
module Insights
  class ProductivityHoursService < BaseService
    def self.call(user:, period: 'week')
      new(user: user, period: period).call
    end

    def initialize(user:, period: 'week')
      super()
      @user = user
      @period = period
    end

    def call
      date_range = calculate_date_range
      visits = fetch_visits(date_range)

      hourly_stats = calculate_hourly_stats(visits)
      day_stats = calculate_day_stats(visits)

      most_productive = hourly_stats.max_by { |h| h[:avg_engagement] }
      least_productive = hourly_stats.min_by { |h| h[:avg_engagement] }

      success_result(
        data: {
          period: @period,
          most_productive_hour: most_productive&.dig(:hour),
          least_productive_hour: least_productive&.dig(:hour),
          hourly_stats: hourly_stats,
          day_of_week_stats: day_stats
        }
      )
    end

    private

    attr_reader :user, :period

    def calculate_date_range
      case period
      when 'week'
        { start: 7.days.ago.beginning_of_day, end: Time.current.end_of_day }
      when 'month'
        { start: 30.days.ago.beginning_of_day, end: Time.current.end_of_day }
      else
        { start: 7.days.ago.beginning_of_day, end: Time.current.end_of_day }
      end
    end

    def fetch_visits(date_range)
      user.page_visits
          .where('visited_at >= ? AND visited_at <= ?', date_range[:start], date_range[:end])
          .valid_data
    end

    def calculate_hourly_stats(visits)
      visits.group("EXTRACT(HOUR FROM visited_at)")
            .select(
              'EXTRACT(HOUR FROM visited_at) as hour',
              'AVG(engagement_rate) as avg_engagement',
              'SUM(duration_seconds) as total_time',
              'COUNT(*) as visit_count'
            )
            .order('hour')
            .map do |row|
              {
                hour: row.hour.to_i,
                avg_engagement: row.avg_engagement&.round(2) || 0.0,
                total_time_seconds: row.total_time || 0,
                visit_count: row.visit_count
              }
            end
    end

    def calculate_day_stats(visits)
      visits.group("EXTRACT(DOW FROM visited_at)")
            .select(
              'EXTRACT(DOW FROM visited_at) as day_num',
              'AVG(engagement_rate) as avg_engagement',
              'SUM(duration_seconds) as total_time'
            )
            .order('day_num')
            .map do |row|
              {
                day: Date::DAYNAMES[row.day_num.to_i],
                avg_engagement: row.avg_engagement&.round(2) || 0.0,
                total_time_seconds: row.total_time || 0
              }
            end
    end
  end
end
```

---

### Controllers

```ruby
# frozen_string_literal: true

# app/controllers/api/v1/insights_controller.rb
module Api
  module V1
    class InsightsController < AuthenticatedController
      # GET /api/v1/insights/daily_summary
      def daily_summary
        result = Insights::DailySummaryService.call(
          user: current_user,
          date: params[:date] || Date.today
        )

        render_service_result(result)
      end

      # GET /api/v1/insights/weekly_summary
      def weekly_summary
        # Implementation similar to daily_summary
        # Uses Insights::WeeklySummaryService
      end

      # GET /api/v1/insights/top_sites
      def top_sites
        result = Insights::TopSitesService.call(
          user: current_user,
          period: params[:period] || 'week',
          limit: params[:limit] || 10,
          sort_by: params[:sort_by] || 'time'
        )

        render_service_result(result)
      end

      # GET /api/v1/insights/recent_activity
      def recent_activity
        result = Insights::RecentActivityService.call(
          user: current_user,
          limit: params[:limit] || 20,
          since: params[:since]
        )

        render_service_result(result)
      end

      # GET /api/v1/insights/productivity_hours
      def productivity_hours
        result = Insights::ProductivityHoursService.call(
          user: current_user,
          period: params[:period] || 'week'
        )

        render_service_result(result)
      end

      private

      def render_service_result(result)
        if result.success?
          render_json_response(
            success: true,
            data: result.data
          )
        else
          render_error_response(
            message: result.message,
            errors: result.errors,
            status: :unprocessable_entity
          )
        end
      end
    end
  end
end
```

---

### Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      namespace :insights do
        get :daily_summary
        get :weekly_summary
        get :top_sites
        get :recent_activity
        get :productivity_hours
      end

      # ... existing routes ...
    end
  end
end
```

---

## Testing

```ruby
# frozen_string_literal: true

# spec/services/insights/daily_summary_service_spec.rb
require 'rails_helper'

RSpec.describe Insights::DailySummaryService do
  describe '.call' do
    let(:user) { create(:user) }
    let(:today) { Date.today }

    before do
      # Create test data
      create_list(:page_visit, 5, user: user, visited_at: today.beginning_of_day + 9.hours, domain: 'github.com')
      create_list(:page_visit, 3, user: user, visited_at: today.beginning_of_day + 14.hours, domain: 'stackoverflow.com')
      create(:page_visit, user: user, visited_at: 1.day.ago)  # Yesterday (should not be included)
    end

    it 'returns daily summary' do
      result = described_class.call(user: user, date: today)

      expect(result.success?).to be true
      expect(result.data[:total_sites_visited]).to eq(8)
      expect(result.data[:unique_domains]).to eq(2)
    end

    it 'includes top domain' do
      result = described_class.call(user: user, date: today)

      expect(result.data[:top_domain][:domain]).to eq('github.com')
      expect(result.data[:top_domain][:visits]).to eq(5)
    end

    it 'includes hourly breakdown' do
      result = described_class.call(user: user, date: today)

      expect(result.data[:hourly_breakdown]).to be_an(Array)
      expect(result.data[:hourly_breakdown].size).to be >= 2
    end
  end
end
```

---

## Performance Considerations

### Caching Strategy

```ruby
# Add caching for expensive queries
def daily_summary
  cache_key = "insights/daily_summary/#{current_user.id}/#{params[:date] || Date.today}"

  cached_result = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
    result = Insights::DailySummaryService.call(
      user: current_user,
      date: params[:date] || Date.today
    )
    result.data
  end

  render_json_response(success: true, data: cached_result)
end
```

### Database Indexes

```ruby
# Add indexes for common queries
add_index :page_visits, [:user_id, :visited_at]
add_index :page_visits, [:user_id, :domain]
add_index :page_visits, [:user_id, :domain, :visited_at]
```

---

## Summary

### New Endpoints

1. ✅ `GET /api/v1/insights/daily_summary` - Day's activity
2. ✅ `GET /api/v1/insights/weekly_summary` - Week's activity
3. ✅ `GET /api/v1/insights/top_sites` - Most visited sites
4. ✅ `GET /api/v1/insights/recent_activity` - Recent sessions
5. ✅ `GET /api/v1/insights/productivity_hours` - Best hours/days

### Benefits

- ✅ **Fast**: Server-side aggregation (no client processing)
- ✅ **Efficient**: Small payloads (summaries not raw data)
- ✅ **Scalable**: Works with millions of records
- ✅ **Cacheable**: 1-hour cache for expensive queries

### Performance

- Daily summary: ~50ms (cached)
- Top sites: ~100ms (indexed queries)
- Recent activity: ~150ms (session grouping)

---

**Status:** Ready for Implementation
**Next:** Create implementation timeline
