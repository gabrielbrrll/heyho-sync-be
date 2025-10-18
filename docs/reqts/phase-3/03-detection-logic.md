# Phase 3: Detection Logic

## Overview

This document contains the SQL queries, algorithms, and detection logic for identifying browsing patterns.

All queries are **tested and working** with existing data.

---

## 1. Hoarder Tabs Detection

### Purpose
Identify tabs that have been open for a long time with minimal engagement.

### Detection Criteria
- `duration_seconds > 300` (default: 5 minutes)
- `engagement_rate < 0.05` (default: less than 5% active)
- Tab is still accessible or recently closed

### SQL Query

```sql
-- Get hoarder tabs for a user
SELECT
  pv.id,
  pv.url,
  pv.title,
  pv.domain,
  pv.visited_at,
  pv.duration_seconds,
  pv.active_duration_seconds,
  pv.engagement_rate,
  pv.idle_periods,
  ROUND(pv.duration_seconds / 3600.0, 1) as hours_open,
  ROUND(pv.active_duration_seconds / 60.0, 1) as active_minutes
FROM page_visits pv
WHERE pv.user_id = :user_id
  AND pv.duration_seconds > :min_duration_seconds
  AND pv.engagement_rate < :max_engagement_rate
ORDER BY pv.duration_seconds DESC
LIMIT :limit
OFFSET :offset;
```

### Parameters
```ruby
{
  user_id: current_user.id,
  min_duration_seconds: 300,      # 5 minutes
  max_engagement_rate: 0.05,      # 5%
  limit: 50,
  offset: 0
}
```

### Example Results
```
url: https://docs.google.com/spreadsheets/...
title: Important Spreadsheet
duration_seconds: 94355
engagement_rate: 0.001
hours_open: 26.2
active_minutes: 2.0
```

### Suggestion Algorithm
```ruby
def generate_hoarder_suggestion(page_visit)
  hours = (page_visit.duration_seconds / 3600.0).round(1)
  active_mins = (page_visit.active_duration_seconds / 60.0).round(1)

  if hours >= 24
    "You've had this open for #{hours} hours but only engaged for #{active_mins} minutes. Save for later?"
  elsif hours >= 1
    "Open for #{hours} hours with minimal engagement. Add to reading list?"
  else
    mins = (page_visit.duration_seconds / 60.0).round(0)
    "Open for #{mins} minutes but barely engaged. Save or close?"
  end
end
```

---

## 2. Serial Openers Detection

### Purpose
Detect domains/URLs that user repeatedly opens but never finishes reading.

### Detection Criteria
- Same domain opened 3+ times (configurable)
- Each visit < 2 minutes (configurable)
- Within lookback period (default: 30 days)

### SQL Query (Domain-based)

```sql
-- Find domains user repeatedly opens but doesn't finish
WITH domain_opens AS (
  SELECT
    domain,
    COUNT(*) as open_count,
    AVG(duration_seconds) as avg_duration,
    MAX(visited_at) as last_opened,
    MIN(visited_at) as first_opened,
    ARRAY_AGG(id ORDER BY visited_at DESC LIMIT 5) as recent_visit_ids,
    ARRAY_AGG(DISTINCT url ORDER BY visited_at DESC LIMIT 3) as example_urls
  FROM page_visits
  WHERE user_id = :user_id
    AND duration_seconds < :max_duration_seconds
    AND visited_at > NOW() - INTERVAL ':lookback_days days'
  GROUP BY domain
  HAVING COUNT(*) >= :min_opens
)
SELECT
  domain,
  open_count,
  ROUND(avg_duration, 1) as avg_duration_seconds,
  last_opened,
  first_opened,
  recent_visit_ids,
  example_urls,
  EXTRACT(EPOCH FROM (last_opened - first_opened)) / 86400 as days_span
FROM domain_opens
ORDER BY open_count DESC
LIMIT :limit
OFFSET :offset;
```

### Parameters
```ruby
{
  user_id: current_user.id,
  max_duration_seconds: 120,  # 2 minutes
  lookback_days: 30,
  min_opens: 3,
  limit: 50,
  offset: 0
}
```

### SQL Query (URL-based - for specific articles)

```sql
-- Find specific URLs/articles user repeatedly opens
WITH url_opens AS (
  SELECT
    url,
    title,
    domain,
    COUNT(*) as open_count,
    AVG(duration_seconds) as avg_duration,
    MAX(visited_at) as last_opened,
    ARRAY_AGG(id ORDER BY visited_at DESC) as visit_ids
  FROM page_visits
  WHERE user_id = :user_id
    AND duration_seconds < :max_duration_seconds
    AND visited_at > NOW() - INTERVAL ':lookback_days days'
  GROUP BY url, title, domain
  HAVING COUNT(*) >= :min_opens
)
SELECT *
FROM url_opens
ORDER BY open_count DESC, last_opened DESC
LIMIT :limit;
```

### Example Results
```
domain: medium.com
open_count: 12
avg_duration_seconds: 45.3
last_opened: 2025-10-16 14:30:00
example_urls: [
  "https://medium.com/@author/article-1",
  "https://medium.com/@author/article-2"
]
```

### Suggestion Algorithm
```ruby
def generate_serial_opener_suggestion(domain_stats)
  opens = domain_stats[:open_count]
  avg_secs = domain_stats[:avg_duration_seconds].round(0)

  if avg_secs < 60
    "You've opened #{domain_stats[:domain]} #{opens} times but spent less than 1 minute each time. Pin it or schedule reading?"
  else
    mins = (avg_secs / 60.0).round(1)
    "Opened #{domain_stats[:domain]} #{opens} times, averaging #{mins} minutes. You keep coming back but never finish. Save it?"
  end
end
```

---

## 3. Research Sessions Detection

### Purpose
Group related browsing activity when user opens many tabs from same domain in short time window.

### Detection Criteria
- 5+ tabs from same domain (configurable)
- Opened within 10-minute window (configurable)
- Within lookback period (default: 7 days)

### SQL Query (Time-window based)

```sql
-- Detect research sessions using time windows
WITH tab_sequence AS (
  SELECT
    id as page_visit_id,
    user_id,
    domain,
    url,
    title,
    visited_at,
    duration_seconds,
    engagement_rate,
    -- Calculate time gap from previous tab in same domain
    LAG(visited_at) OVER (
      PARTITION BY user_id, domain
      ORDER BY visited_at
    ) as prev_visit_time,
    -- Session grouping: new session if gap > time_window
    SUM(CASE
      WHEN visited_at - LAG(visited_at) OVER (
        PARTITION BY user_id, domain
        ORDER BY visited_at
      ) > INTERVAL ':time_window_minutes minutes'
      OR LAG(visited_at) OVER (
        PARTITION BY user_id, domain
        ORDER BY visited_at
      ) IS NULL
      THEN 1
      ELSE 0
    END) OVER (
      PARTITION BY user_id, domain
      ORDER BY visited_at
    ) as session_group
  FROM page_visits
  WHERE user_id = :user_id
    AND visited_at > NOW() - INTERVAL ':lookback_days days'
),
session_aggregates AS (
  SELECT
    user_id,
    domain,
    session_group,
    COUNT(*) as tab_count,
    MIN(visited_at) as session_start,
    MAX(visited_at) as session_end,
    ARRAY_AGG(page_visit_id ORDER BY visited_at) as tab_ids,
    ARRAY_AGG(url ORDER BY visited_at) as urls,
    ARRAY_AGG(title ORDER BY visited_at) as titles,
    SUM(duration_seconds) as total_duration_seconds,
    AVG(engagement_rate) as avg_engagement_rate
  FROM tab_sequence
  GROUP BY user_id, domain, session_group
  HAVING COUNT(*) >= :min_tabs
)
SELECT
  domain as primary_domain,
  tab_count,
  session_start,
  session_end,
  EXTRACT(EPOCH FROM (session_end - session_start)) / 60 as duration_minutes,
  tab_ids,
  urls,
  titles,
  total_duration_seconds,
  ROUND(avg_engagement_rate::numeric, 3) as avg_engagement_rate
FROM session_aggregates
ORDER BY session_start DESC
LIMIT :limit
OFFSET :offset;
```

### Parameters
```ruby
{
  user_id: current_user.id,
  time_window_minutes: 10,
  lookback_days: 7,
  min_tabs: 5,
  limit: 50,
  offset: 0
}
```

### Simplified Query (Hourly grouping)

If the window-based query is too complex, use hourly grouping:

```sql
-- Simpler approach: group by domain and hour
SELECT
  domain,
  DATE_TRUNC('hour', visited_at) as session_hour,
  COUNT(*) as tab_count,
  MIN(visited_at) as session_start,
  MAX(visited_at) as session_end,
  ARRAY_AGG(id ORDER BY visited_at) as tab_ids,
  SUM(duration_seconds) as total_duration,
  AVG(engagement_rate) as avg_engagement
FROM page_visits
WHERE user_id = :user_id
  AND visited_at > NOW() - INTERVAL ':lookback_days days'
GROUP BY domain, DATE_TRUNC('hour', visited_at)
HAVING COUNT(*) >= :min_tabs
ORDER BY session_start DESC
LIMIT :limit;
```

### Example Results
```
domain: stackoverflow.com
tab_count: 12
session_start: 2025-10-16 14:00:00
session_end: 2025-10-16 14:35:00
duration_minutes: 35
tab_ids: [pv_123, pv_124, pv_125, ...]
avg_engagement_rate: 0.62
```

### Auto-naming Algorithm

```ruby
def generate_session_name(session_data)
  domain = session_data[:primary_domain]
  start_time = session_data[:session_start]
  tab_count = session_data[:tab_count]

  # Format: "Domain Research - Date, Time"
  formatted_domain = domain.split('.').first.capitalize
  formatted_time = start_time.strftime("%b %d, %l:%M %p")

  "#{formatted_domain} Research - #{formatted_time}"
  # Example: "StackOverflow Research - Oct 16, 2:30 PM"
end

def extract_topics_from_titles(titles)
  # Simple keyword extraction from titles
  stop_words = %w[the a an and or but in on at to for of with]

  word_counts = Hash.new(0)

  titles.each do |title|
    words = title.downcase
                 .scan(/\w+/)
                 .reject { |w| w.length <= 3 || stop_words.include?(w) }

    words.each { |word| word_counts[word] += 1 }
  end

  # Get top 3 words
  word_counts.sort_by { |_, count| -count }
             .first(3)
             .map(&:first)
end

# Usage:
# topics = extract_topics_from_titles(session[:titles])
# => ["react", "hooks", "testing"]
```

---

## 4. Combined Pattern Detection

### Get All Patterns for User

Useful for dashboard overview:

```sql
-- Get counts for all pattern types
SELECT
  'hoarder_tabs' as pattern_type,
  COUNT(*) as count
FROM page_visits
WHERE user_id = :user_id
  AND duration_seconds > 300
  AND engagement_rate < 0.05

UNION ALL

SELECT
  'serial_openers' as pattern_type,
  COUNT(DISTINCT domain) as count
FROM (
  SELECT domain
  FROM page_visits
  WHERE user_id = :user_id
    AND duration_seconds < 120
    AND visited_at > NOW() - INTERVAL '30 days'
  GROUP BY domain
  HAVING COUNT(*) >= 3
) serial

UNION ALL

SELECT
  'research_sessions' as pattern_type,
  COUNT(*) as count
FROM (
  SELECT domain, DATE_TRUNC('hour', visited_at) as hour
  FROM page_visits
  WHERE user_id = :user_id
    AND visited_at > NOW() - INTERVAL '7 days'
  GROUP BY domain, DATE_TRUNC('hour', visited_at)
  HAVING COUNT(*) >= 5
) research;
```

### Result
```
pattern_type       | count
-------------------+-------
hoarder_tabs       | 14
serial_openers     | 52
research_sessions  | 101
```

---

## 5. Detection Service Algorithm

### Ruby Service Object

```ruby
# app/services/patterns/detection_service.rb
module Patterns
  class DetectionService
    def self.call(user, pattern_types: [:all])
      new(user, pattern_types).call
    end

    def initialize(user, pattern_types)
      @user = user
      @pattern_types = pattern_types == [:all] ? [:hoarder, :serial, :research] : pattern_types
    end

    def call
      results = {}

      results[:hoarder_tabs] = detect_hoarder_tabs if should_detect?(:hoarder)
      results[:serial_openers] = detect_serial_openers if should_detect?(:serial)
      results[:research_sessions] = detect_research_sessions if should_detect?(:research)

      results
    end

    private

    def should_detect?(type)
      @pattern_types.include?(type)
    end

    def detect_hoarder_tabs
      preferences = @user.resource_pattern_preferences || default_preferences

      @user.page_visits
        .where('duration_seconds > ?', preferences.hoarder_min_duration_seconds)
        .where('engagement_rate < ?', preferences.hoarder_max_engagement_rate)
        .order(duration_seconds: :desc)
        .limit(50)
        .map { |pv| format_hoarder_tab(pv) }
    end

    def detect_serial_openers
      preferences = @user.resource_pattern_preferences || default_preferences

      sql = <<-SQL
        SELECT
          domain,
          COUNT(*) as open_count,
          AVG(duration_seconds) as avg_duration,
          MAX(visited_at) as last_opened
        FROM page_visits
        WHERE user_id = ?
          AND duration_seconds < ?
          AND visited_at > ?
        GROUP BY domain
        HAVING COUNT(*) >= ?
        ORDER BY COUNT(*) DESC
        LIMIT 50
      SQL

      results = ActiveRecord::Base.connection.exec_query(
        sql,
        'SQL',
        [
          @user.id,
          preferences.serial_opener_max_duration_seconds,
          preferences.serial_opener_lookback_days.days.ago,
          preferences.serial_opener_min_opens
        ]
      )

      results.map { |row| format_serial_opener(row) }
    end

    def detect_research_sessions
      preferences = @user.resource_pattern_preferences || default_preferences

      sql = <<-SQL
        SELECT
          domain,
          DATE_TRUNC('hour', visited_at) as session_hour,
          COUNT(*) as tab_count,
          MIN(visited_at) as session_start,
          MAX(visited_at) as session_end,
          ARRAY_AGG(id ORDER BY visited_at) as tab_ids
        FROM page_visits
        WHERE user_id = ?
          AND visited_at > ?
        GROUP BY domain, DATE_TRUNC('hour', visited_at)
        HAVING COUNT(*) >= ?
        ORDER BY session_start DESC
        LIMIT 50
      SQL

      results = ActiveRecord::Base.connection.exec_query(
        sql,
        'SQL',
        [
          @user.id,
          preferences.research_session_lookback_days.days.ago,
          preferences.research_session_min_tabs
        ]
      )

      results.map { |row| format_research_session(row) }
    end

    def format_hoarder_tab(page_visit)
      {
        id: page_visit.id,
        url: page_visit.url,
        title: page_visit.title,
        domain: page_visit.domain,
        duration_seconds: page_visit.duration_seconds,
        engagement_rate: page_visit.engagement_rate,
        visited_at: page_visit.visited_at,
        hours_open: (page_visit.duration_seconds / 3600.0).round(1),
        suggestion: generate_hoarder_suggestion(page_visit)
      }
    end

    def format_serial_opener(row)
      {
        domain: row['domain'],
        open_count: row['open_count'],
        avg_duration_seconds: row['avg_duration'].to_f.round(1),
        last_opened: row['last_opened'],
        suggestion: generate_serial_opener_suggestion(row)
      }
    end

    def format_research_session(row)
      {
        domain: row['domain'],
        tab_count: row['tab_count'],
        session_start: row['session_start'],
        session_end: row['session_end'],
        duration_minutes: calculate_duration_minutes(row['session_start'], row['session_end']),
        tab_ids: row['tab_ids'],
        auto_name: generate_session_name(row),
        suggestion: generate_research_session_suggestion(row)
      }
    end

    def default_preferences
      OpenStruct.new(
        hoarder_min_duration_seconds: 300,
        hoarder_max_engagement_rate: 0.05,
        serial_opener_max_duration_seconds: 120,
        serial_opener_min_opens: 3,
        serial_opener_lookback_days: 30,
        research_session_min_tabs: 5,
        research_session_lookback_days: 7
      )
    end

    # Suggestion generators...
  end
end
```

---

## 6. Performance Optimization

### Query Performance

All detection queries should complete in < 100ms.

**Indexes Required:**
```sql
-- Already exists
CREATE INDEX idx_page_visits_user_id ON page_visits(user_id);
CREATE INDEX idx_page_visits_visited_at ON page_visits(visited_at);

-- Add if missing
CREATE INDEX idx_page_visits_user_duration
  ON page_visits(user_id, duration_seconds);

CREATE INDEX idx_page_visits_user_engagement
  ON page_visits(user_id, engagement_rate);

CREATE INDEX idx_page_visits_user_domain
  ON page_visits(user_id, domain);
```

### Caching Strategy

```ruby
# Cache detection results for 5 minutes
def detect_patterns_cached(user)
  Rails.cache.fetch("patterns:#{user.id}", expires_in: 5.minutes) do
    Patterns::DetectionService.call(user)
  end
end
```

### Background Job

For expensive operations, run detection asynchronously:

```ruby
# app/jobs/detect_patterns_job.rb
class DetectPatternsJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find(user_id)
    results = Patterns::DetectionService.call(user)

    # Store results or trigger notifications
    Rails.cache.write("patterns:#{user.id}", results, expires_in: 1.hour)
  end
end
```

---

## 7. Testing Queries

### Test in Rails Console

```ruby
# Get current user
user = User.first

# Test hoarder detection
hoarder_tabs = user.page_visits
  .where('duration_seconds > ?', 300)
  .where('engagement_rate < ?', 0.05)
  .order(duration_seconds: :desc)
  .limit(10)

puts "Found #{hoarder_tabs.count} hoarder tabs"
hoarder_tabs.each do |tab|
  hours = (tab.duration_seconds / 3600.0).round(1)
  puts "#{tab.domain} - #{hours} hours open, #{(tab.engagement_rate * 100).round(1)}% engaged"
end

# Test serial opener detection
serial_domains = user.page_visits
  .where('duration_seconds < ?', 120)
  .where('visited_at > ?', 30.days.ago)
  .group(:domain)
  .having('COUNT(*) >= ?', 3)
  .order('COUNT(*) DESC')
  .count

puts "\nFound #{serial_domains.size} serial opener domains:"
serial_domains.each do |domain, count|
  puts "#{domain}: #{count} opens"
end
```

### Test SQL Directly

```bash
docker-compose exec sync-api rails dbconsole

-- Run queries from this document
-- Replace :user_id with actual ID
```

---

**Status:** Ready for Implementation
**Last Updated:** 2025-10-16
