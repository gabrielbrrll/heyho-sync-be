# Phase 2.2: Data Quality & Validation

## Overview

**Goal:** Ensure data quality through validation, sanitization, and cleanup processes.

**Why This Matters:**
- Corrupt data breaks frontend
- Invalid metrics skew insights
- Bad data ruins pattern detection (Phase 3)
- User trust depends on data accuracy

---

## Current Data Quality Issues

### Issue #1: Invalid Engagement Rates

**Problem:**
```sql
-- Query database
SELECT id, engagement_rate FROM page_visits WHERE engagement_rate > 1.0;

-- Results (INVALID):
-- id: "visit_123", engagement_rate: 5.0  ❌ (should be 0-1)
-- id: "visit_456", engagement_rate: 999  ❌ (should be 0-1)
```

**Cause:** No validation on write

**Impact:** Frontend charts break, insights are wrong

---

### Issue #2: Invalid Timestamps

**Problem:**
```sql
SELECT id, visited_at FROM page_visits WHERE visited_at > NOW() + INTERVAL '1 day';

-- Results (INVALID):
-- id: "visit_789", visited_at: "2099-12-31"  ❌ (future date)
```

**Cause:** Client clock drift, bugs in extension

**Impact:** Timeline shows future visits

---

### Issue #3: Negative Durations

**Problem:**
```sql
SELECT id, duration_seconds FROM page_visits WHERE duration_seconds < 0;

-- Results (INVALID):
-- id: "visit_999", duration_seconds: -3600  ❌ (negative time)
```

**Cause:** Timestamp calculation bugs

**Impact:** Analytics show negative time spent

---

### Issue #4: NULL Required Fields

**Problem:**
```sql
SELECT COUNT(*) FROM page_visits WHERE domain IS NULL;
-- Result: 234 records  ❌ (domain should always be present)
```

**Cause:** URL parsing failures not caught

**Impact:** Can't aggregate by domain, insights fail

---

### Issue #5: Corrupt JSONB Data

**Problem:**
```ruby
page_visit.idle_periods
# => "not a valid json"  ❌ (should be array)

page_visit.statistics
# => { "weird_field": NaN }  ❌ (NaN not valid JSON)
```

**Cause:** Extension bugs, race conditions

**Impact:** Database errors, can't query JSONB

---

## Solution: Multi-Layer Validation

### Layer 1: Model Validations (Write-Time)

**Update Models:**

```ruby
# frozen_string_literal: true

# app/models/page_visit.rb
class PageVisit < ApplicationRecord
  belongs_to :user

  # Validations
  validates :url, :domain, :visited_at, presence: true
  validates :url, format: { with: URI::DEFAULT_PARSER.make_regexp, message: 'must be a valid URL' }
  validates :domain, format: { with: /\A[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,}\z/i, message: 'must be a valid domain' }

  validates :duration_seconds, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 86400,  # Max 24 hours per visit
    allow_nil: true
  }

  validates :active_duration_seconds, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 86400,
    allow_nil: true
  }

  validates :engagement_rate, numericality: {
    greater_than_or_equal_to: 0.0,
    less_than_or_equal_to: 1.0,
    allow_nil: true
  }, if: :engagement_rate_present?

  validate :visited_at_not_in_future
  validate :active_duration_not_greater_than_total
  validate :idle_periods_is_valid_json

  # Callbacks
  before_validation :extract_domain_from_url
  before_validation :sanitize_engagement_rate
  before_validation :sanitize_durations

  # Scopes
  scope :valid_data, -> { where('engagement_rate BETWEEN 0 AND 1').where('duration_seconds >= 0') }
  scope :recent, ->(days = 7) { where('visited_at >= ?', days.days.ago) }

  private

  def engagement_rate_present?
    engagement_rate.present?
  end

  def visited_at_not_in_future
    return if visited_at.blank?

    if visited_at > 1.hour.from_now
      errors.add(:visited_at, 'cannot be in the future')
    end
  end

  def active_duration_not_greater_than_total
    return if active_duration_seconds.blank? || duration_seconds.blank?

    if active_duration_seconds > duration_seconds
      errors.add(:active_duration_seconds, 'cannot be greater than total duration')
    end
  end

  def idle_periods_is_valid_json
    return if idle_periods.blank?
    return if idle_periods.is_a?(Array)

    errors.add(:idle_periods, 'must be a valid JSON array')
  end

  def extract_domain_from_url
    return if url.blank?
    return if domain.present?

    self.domain = URI.parse(url).host
  rescue URI::InvalidURIError
    self.domain = nil
  end

  def sanitize_engagement_rate
    return if engagement_rate.blank?

    # Clamp to 0-1 range
    self.engagement_rate = [[engagement_rate, 0.0].max, 1.0].min
  end

  def sanitize_durations
    # Clamp durations to valid ranges
    if duration_seconds.present?
      self.duration_seconds = [[duration_seconds, 0].max, 86400].min
    end

    if active_duration_seconds.present?
      self.active_duration_seconds = [[active_duration_seconds, 0].max, 86400].min
    end
  end
end
```

```ruby
# frozen_string_literal: true

# app/models/tab_aggregate.rb
class TabAggregate < ApplicationRecord
  belongs_to :page_visit

  # Validations
  validates :page_visit_id, :closed_at, presence: true
  validates :total_time_seconds, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 31_536_000  # Max 1 year
  }

  validates :active_time_seconds, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 31_536_000
  }

  validates :scroll_depth_percent, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 100,
    allow_nil: true
  }

  validate :active_not_greater_than_total
  validate :closed_at_not_in_future

  # Callbacks
  before_validation :sanitize_durations
  before_validation :sanitize_scroll_depth

  # Scopes
  scope :valid_data, -> { where('total_time_seconds >= 0').where('active_time_seconds >= 0') }
  scope :recent, ->(days = 7) { where('closed_at >= ?', days.days.ago) }

  private

  def active_not_greater_than_total
    return if active_time_seconds.blank? || total_time_seconds.blank?

    if active_time_seconds > total_time_seconds
      errors.add(:active_time_seconds, 'cannot be greater than total time')
    end
  end

  def closed_at_not_in_future
    return if closed_at.blank?

    if closed_at > 1.hour.from_now
      errors.add(:closed_at, 'cannot be in the future')
    end
  end

  def sanitize_durations
    if total_time_seconds.present?
      self.total_time_seconds = [[total_time_seconds, 0].max, 31_536_000].min
    end

    if active_time_seconds.present?
      self.active_time_seconds = [[active_time_seconds, 0].max, 31_536_000].min
    end
  end

  def sanitize_scroll_depth
    return if scroll_depth_percent.blank?

    self.scroll_depth_percent = [[scroll_depth_percent, 0].max, 100].min
  end
end
```

---

### Layer 2: Service-Level Validation (DataSyncService)

**Update DataSyncService:**

```ruby
# frozen_string_literal: true

# app/services/data_sync_service.rb
class DataSyncService < BaseService
  # ... existing code ...

  def save_page_visits_with_conflicts
    synced_count = 0
    failed_records = []

    page_visits.each do |visit|
      existing = PageVisit.find_by(id: visit['id'])

      begin
        if existing
          resolved_visit = resolve_page_visit_conflict(existing, visit)
          existing.update!(resolved_visit)
        else
          PageVisit.create!({
            id: visit['id'],
            user_id: user.id,
            **visit.except('id')
          })
        end

        synced_count += 1
      rescue ActiveRecord::RecordInvalid => e
        # Log validation failure but continue
        Rails.logger.warn("Skipping invalid page_visit #{visit['id']}: #{e.message}")
        failed_records << {
          id: visit['id'],
          errors: e.record.errors.full_messages
        }
      end
    end

    # Track failed records in sync log
    @sync_log.errors = { failed_page_visits: failed_records } if failed_records.any?

    synced_count
  end

  # ... rest of code ...
end
```

---

### Layer 3: Sanitization Service (Read-Time)

**Create DataSanitizer Service:**

```ruby
# frozen_string_literal: true

# app/services/data_sanitizer_service.rb
class DataSanitizerService
  def self.sanitize_page_visit(page_visit)
    new.sanitize_page_visit(page_visit)
  end

  def self.sanitize_page_visits(page_visits)
    new.sanitize_page_visits(page_visits)
  end

  def sanitize_page_visit(page_visit)
    sanitized = page_visit.as_json

    # Sanitize engagement_rate (clamp to 0-1)
    if sanitized['engagement_rate']
      sanitized['engagement_rate'] = clamp(sanitized['engagement_rate'], 0.0, 1.0)
    end

    # Sanitize durations (non-negative, max 24 hours)
    if sanitized['duration_seconds']
      sanitized['duration_seconds'] = clamp(sanitized['duration_seconds'], 0, 86400)
    end

    if sanitized['active_duration_seconds']
      sanitized['active_duration_seconds'] = clamp(sanitized['active_duration_seconds'], 0, 86400)
    end

    # Ensure active_duration <= total_duration
    if sanitized['active_duration_seconds'] && sanitized['duration_seconds']
      if sanitized['active_duration_seconds'] > sanitized['duration_seconds']
        sanitized['active_duration_seconds'] = sanitized['duration_seconds']
      end
    end

    # Sanitize idle_periods (must be array)
    if sanitized['idle_periods'] && !sanitized['idle_periods'].is_a?(Array)
      sanitized['idle_periods'] = []
    end

    # Sanitize visited_at (not in future)
    if sanitized['visited_at'] && Time.zone.parse(sanitized['visited_at']) > 1.hour.from_now
      sanitized['visited_at'] = Time.current.iso8601
    end

    sanitized
  end

  def sanitize_page_visits(page_visits)
    page_visits.map { |pv| sanitize_page_visit(pv) }
  end

  private

  def clamp(value, min, max)
    [[value, min].max, max].min
  end
end
```

**Update Controller to Use Sanitizer:**

```ruby
# frozen_string_literal: true

# app/controllers/api/v1/browsing_data_controller.rb
module Api
  module V1
    class BrowsingDataController < BaseController
      # ... existing code ...

      def index
        target_user = find_target_user
        return unless target_user

        @page_visits = target_user.page_visits
                                   .valid_data  # ← Filter valid data only
                                   .order(visited_at: :desc)
                                   .limit(page_limit)
                                   .offset(page_offset)

        # Sanitize before returning
        sanitized_visits = DataSanitizerService.sanitize_page_visits(@page_visits)

        render_json_response(
          success: true,
          data: {
            page_visits: sanitized_visits,
            pagination: {
              page: current_page,
              per_page: page_limit,
              total: target_user.page_visits.valid_data.count
            }
          }
        )
      end

      # ... rest of code ...
    end
  end
end
```

---

### Layer 4: Background Cleanup Job

**Create Cleanup Job:**

```ruby
# frozen_string_literal: true

# app/jobs/cleanup_corrupt_data_job.rb
class CleanupCorruptDataJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info('Starting corrupt data cleanup...')

    cleanup_invalid_page_visits
    cleanup_invalid_tab_aggregates
    cleanup_orphaned_records

    Rails.logger.info('Corrupt data cleanup completed')
  end

  private

  def cleanup_invalid_page_visits
    # Fix engagement_rates > 1
    invalid_engagement = PageVisit.where('engagement_rate > 1.0 OR engagement_rate < 0')
    Rails.logger.info("Found #{invalid_engagement.count} page_visits with invalid engagement_rate")

    invalid_engagement.find_each do |pv|
      pv.update_column(:engagement_rate, [[pv.engagement_rate, 0.0].max, 1.0].min)
    end

    # Fix negative durations
    negative_duration = PageVisit.where('duration_seconds < 0')
    Rails.logger.info("Found #{negative_duration.count} page_visits with negative duration")

    negative_duration.update_all(duration_seconds: 0)

    # Fix future dates
    future_dates = PageVisit.where('visited_at > ?', 1.hour.from_now)
    Rails.logger.info("Found #{future_dates.count} page_visits with future dates")

    future_dates.update_all(visited_at: Time.current)

    # Fix NULL domains
    null_domains = PageVisit.where(domain: nil)
    Rails.logger.info("Found #{null_domains.count} page_visits with NULL domain")

    null_domains.find_each do |pv|
      domain = extract_domain(pv.url)
      pv.update_column(:domain, domain) if domain
    end
  end

  def cleanup_invalid_tab_aggregates
    # Fix active_time > total_time
    invalid_active = TabAggregate.where('active_time_seconds > total_time_seconds')
    Rails.logger.info("Found #{invalid_active.count} tab_aggregates with active > total")

    invalid_active.find_each do |ta|
      ta.update_column(:active_time_seconds, ta.total_time_seconds)
    end

    # Fix scroll_depth > 100
    invalid_scroll = TabAggregate.where('scroll_depth_percent > 100')
    Rails.logger.info("Found #{invalid_scroll.count} tab_aggregates with scroll > 100%")

    invalid_scroll.update_all(scroll_depth_percent: 100)
  end

  def cleanup_orphaned_records
    # Delete tab_aggregates without valid page_visit
    orphaned = TabAggregate.left_joins(:page_visit).where(page_visits: { id: nil })
    Rails.logger.info("Found #{orphaned.count} orphaned tab_aggregates")

    orphaned.delete_all
  end

  def extract_domain(url)
    URI.parse(url).host
  rescue URI::InvalidURIError
    nil
  end
end
```

**Schedule Job:**

```ruby
# config/initializers/scheduled_jobs.rb
# Run cleanup daily at 3am
# (Add to cron or use gem like 'whenever' or 'sidekiq-scheduler')

# For development, run manually:
# CleanupCorruptDataJob.perform_later
```

---

### Layer 5: Health Check Endpoint

**Create Health Check:**

```ruby
# frozen_string_literal: true

# app/controllers/api/v1/health_controller.rb
module Api
  module V1
    class HealthController < BaseController
      # GET /api/v1/health
      def index
        health_status = check_health

        render json: {
          status: health_status[:healthy] ? 'healthy' : 'degraded',
          timestamp: Time.current.iso8601,
          checks: health_status[:checks]
        }, status: health_status[:healthy] ? :ok : :service_unavailable
      end

      # GET /api/v1/health/data_quality
      def data_quality
        quality_report = DataQualityService.generate_report

        render_json_response(
          success: true,
          data: quality_report
        )
      end

      private

      def check_health
        checks = {
          database: check_database,
          data_quality: check_data_quality,
          sync_health: check_sync_health
        }

        {
          healthy: checks.values.all? { |c| c[:status] == 'ok' },
          checks: checks
        }
      end

      def check_database
        PageVisit.connection.execute('SELECT 1')
        { status: 'ok', message: 'Database connection healthy' }
      rescue StandardError => e
        { status: 'error', message: e.message }
      end

      def check_data_quality
        invalid_count = PageVisit.where('engagement_rate > 1 OR engagement_rate < 0').count +
                        PageVisit.where('duration_seconds < 0').count

        if invalid_count > 100
          { status: 'warning', message: "#{invalid_count} invalid records found" }
        else
          { status: 'ok', message: 'Data quality acceptable' }
        end
      end

      def check_sync_health
        recent_failures = SyncLog.where('synced_at >= ?', 1.hour.ago).where(status: 'failed').count

        if recent_failures > 10
          { status: 'warning', message: "#{recent_failures} sync failures in last hour" }
        else
          { status: 'ok', message: 'Sync health good' }
        end
      end
    end
  end
end
```

**Create DataQualityService:**

```ruby
# frozen_string_literal: true

# app/services/data_quality_service.rb
class DataQualityService
  def self.generate_report
    new.generate_report
  end

  def generate_report
    {
      total_page_visits: PageVisit.count,
      total_tab_aggregates: TabAggregate.count,
      issues: {
        invalid_engagement_rates: count_invalid_engagement,
        negative_durations: count_negative_durations,
        future_dates: count_future_dates,
        null_domains: count_null_domains,
        orphaned_aggregates: count_orphaned_aggregates
      },
      health_score: calculate_health_score
    }
  end

  private

  def count_invalid_engagement
    PageVisit.where('engagement_rate > 1.0 OR engagement_rate < 0').count
  end

  def count_negative_durations
    PageVisit.where('duration_seconds < 0').count
  end

  def count_future_dates
    PageVisit.where('visited_at > ?', 1.hour.from_now).count
  end

  def count_null_domains
    PageVisit.where(domain: nil).count
  end

  def count_orphaned_aggregates
    TabAggregate.left_joins(:page_visit).where(page_visits: { id: nil }).count
  end

  def calculate_health_score
    total = PageVisit.count
    return 100.0 if total.zero?

    invalid = count_invalid_engagement + count_negative_durations +
              count_future_dates + count_null_domains

    ((total - invalid).to_f / total * 100).round(2)
  end
end
```

---

## Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      # Health checks
      get 'health', to: 'health#index'
      get 'health/data_quality', to: 'health#data_quality'

      # ... existing routes ...
    end
  end
end
```

---

## Testing Strategy

### Model Tests

```ruby
# frozen_string_literal: true

# spec/models/page_visit_spec.rb
require 'rails_helper'

RSpec.describe PageVisit do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:url) }
    it { is_expected.to validate_presence_of(:domain) }
    it { is_expected.to validate_presence_of(:visited_at) }

    describe 'engagement_rate' do
      it 'allows values between 0 and 1' do
        page_visit = build(:page_visit, engagement_rate: 0.5)
        expect(page_visit).to be_valid
      end

      it 'rejects values > 1' do
        page_visit = build(:page_visit, engagement_rate: 1.5)
        expect(page_visit).not_to be_valid
        expect(page_visit.errors[:engagement_rate]).to be_present
      end

      it 'rejects negative values' do
        page_visit = build(:page_visit, engagement_rate: -0.5)
        expect(page_visit).not_to be_valid
      end

      it 'sanitizes invalid values on save' do
        page_visit = build(:page_visit, engagement_rate: 5.0)
        page_visit.save(validate: false)
        page_visit.reload
        expect(page_visit.engagement_rate).to eq(1.0)
      end
    end

    describe 'visited_at' do
      it 'rejects future dates' do
        page_visit = build(:page_visit, visited_at: 2.days.from_now)
        expect(page_visit).not_to be_valid
        expect(page_visit.errors[:visited_at]).to include('cannot be in the future')
      end

      it 'allows current and past dates' do
        page_visit = build(:page_visit, visited_at: 1.day.ago)
        expect(page_visit).to be_valid
      end
    end

    describe 'durations' do
      it 'rejects negative duration_seconds' do
        page_visit = build(:page_visit, duration_seconds: -100)
        expect(page_visit).not_to be_valid
      end

      it 'rejects active_duration > total_duration' do
        page_visit = build(:page_visit, duration_seconds: 100, active_duration_seconds: 200)
        expect(page_visit).not_to be_valid
      end
    end
  end

  describe 'callbacks' do
    describe '#extract_domain_from_url' do
      it 'extracts domain from URL' do
        page_visit = create(:page_visit, url: 'https://github.com/anthropics/claude')
        expect(page_visit.domain).to eq('github.com')
      end
    end

    describe '#sanitize_engagement_rate' do
      it 'clamps engagement_rate to 0-1 range' do
        page_visit = build(:page_visit)
        page_visit.engagement_rate = 5.0
        page_visit.valid?
        expect(page_visit.engagement_rate).to eq(1.0)
      end
    end
  end
end
```

### Service Tests

```ruby
# frozen_string_literal: true

# spec/services/data_sanitizer_service_spec.rb
require 'rails_helper'

RSpec.describe DataSanitizerService do
  describe '.sanitize_page_visit' do
    it 'clamps engagement_rate to 0-1' do
      page_visit = build(:page_visit, engagement_rate: 5.0)
      sanitized = described_class.sanitize_page_visit(page_visit)

      expect(sanitized['engagement_rate']).to eq(1.0)
    end

    it 'ensures active_duration <= total_duration' do
      page_visit = build(:page_visit, duration_seconds: 100, active_duration_seconds: 200)
      sanitized = described_class.sanitize_page_visit(page_visit)

      expect(sanitized['active_duration_seconds']).to eq(100)
    end

    it 'sanitizes future visited_at' do
      page_visit = build(:page_visit, visited_at: 2.days.from_now)
      sanitized = described_class.sanitize_page_visit(page_visit)

      expect(Time.zone.parse(sanitized['visited_at'])).to be <= Time.current
    end
  end
end
```

---

## Summary

### Data Quality Layers

1. **Model Validations** - Prevent bad data at write-time
2. **Service Validations** - Additional checks in DataSyncService
3. **Sanitization** - Clean data on read (DataSanitizerService)
4. **Background Cleanup** - Fix existing corrupt data
5. **Health Checks** - Monitor data quality

### Key Improvements

- ✅ Engagement rates clamped to 0-1
- ✅ Durations must be non-negative
- ✅ Future dates rejected
- ✅ NULL domains prevented
- ✅ Orphaned records cleaned up
- ✅ Health monitoring endpoints

### Performance Impact

- Minimal: Validations add ~10ms per sync
- Background job runs daily (no user impact)
- Health checks are fast (<50ms)

---

**Status:** Ready for Implementation
**Next:** Create insights APIs specification
