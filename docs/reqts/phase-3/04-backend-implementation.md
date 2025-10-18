# Phase 3: Backend Implementation

## Overview

This document outlines the Rails backend implementation: models, controllers, services, and background jobs.

---

## Project Structure

```
app/
├── models/
│   ├── reading_list_item.rb
│   ├── research_session.rb
│   ├── research_session_tab.rb
│   └── resource_pattern_preference.rb
│
├── controllers/
│   └── api/v1/
│       ├── patterns_controller.rb
│       ├── reading_list_controller.rb
│       ├── research_sessions_controller.rb
│       └── pattern_preferences_controller.rb
│
├── services/
│   └── patterns/
│       ├── detection_service.rb
│       ├── hoarder_detector.rb
│       ├── serial_opener_detector.rb
│       └── research_session_detector.rb
│
└── jobs/
    ├── detect_patterns_job.rb
    └── generate_weekly_digest_job.rb
```

---

## Models

### 1. ReadingListItem

**File:** `app/models/reading_list_item.rb`

```ruby
# frozen_string_literal: true

class ReadingListItem < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :page_visit, optional: true, foreign_key: 'page_visit_id', primary_key: 'id'

  # Validations
  validates :url, presence: true, uniqueness: { scope: :user_id }
  validates :status, inclusion: { in: %w[unread reading completed dismissed] }
  validates :added_from, inclusion: {
    in: %w[hoarder_detection manual_save serial_opener research_session api_import],
    allow_nil: true
  }

  # Scopes
  scope :unread, -> { where(status: 'unread') }
  scope :reading, -> { where(status: 'reading') }
  scope :completed, -> { where(status: 'completed') }
  scope :dismissed, -> { where(status: 'dismissed') }
  scope :scheduled, -> { where.not(scheduled_for: nil).where(status: 'unread') }
  scope :recent, -> { order(added_at: :desc) }

  # Callbacks
  before_validation :extract_domain_from_url, if: -> { url.present? && domain.blank? }
  before_validation :set_added_at, on: :create
  after_update :set_completed_at, if: -> { saved_change_to_status? && status == 'completed' }
  after_update :set_dismissed_at, if: -> { saved_change_to_status? && status == 'dismissed' }

  # Class methods
  def self.completion_rate(user)
    total = user.reading_list_items.where.not(status: 'dismissed').count
    return 0 if total.zero?

    completed = user.reading_list_items.completed.count
    (completed.to_f / total * 100).round(1)
  end

  # Instance methods
  def mark_completed!
    update!(status: 'completed', completed_at: Time.current)
  end

  def mark_dismissed!
    update!(status: 'dismissed', dismissed_at: Time.current)
  end

  def estimated_read_time_minutes
    return nil unless estimated_read_time

    (estimated_read_time / 60.0).round(0)
  end

  private

  def extract_domain_from_url
    uri = URI.parse(url)
    self.domain = uri.host&.sub(/^www\./, '')
  rescue URI::InvalidURIError
    self.domain = nil
  end

  def set_added_at
    self.added_at ||= Time.current
  end

  def set_completed_at
    self.completed_at = Time.current
  end

  def set_dismissed_at
    self.dismissed_at = Time.current
  end
end
```

---

### 2. ResearchSession

**File:** `app/models/research_session.rb`

```ruby
# frozen_string_literal: true

class ResearchSession < ApplicationRecord
  # Associations
  belongs_to :user
  has_many :research_session_tabs, dependent: :destroy
  has_many :page_visits, through: :research_session_tabs

  # Validations
  validates :session_name, presence: true
  validates :session_start, presence: true
  validates :session_end, presence: true
  validates :tab_count, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: %w[detected saved restored dismissed] }
  validate :session_end_after_start

  # Scopes
  scope :detected, -> { where(status: 'detected') }
  scope :saved, -> { where(status: 'saved') }
  scope :restored, -> { where(status: 'restored') }
  scope :dismissed, -> { where(status: 'dismissed') }
  scope :recent, -> { order(session_start: :desc) }
  scope :by_domain, ->(domain) { where(primary_domain: domain) }

  # Callbacks
  after_initialize :set_defaults, if: :new_record?

  # Instance methods
  def mark_saved!
    update!(status: 'saved', saved_at: Time.current)
  end

  def mark_restored!
    increment!(:restore_count)
    update!(status: 'restored', last_restored_at: Time.current)
  end

  def mark_dismissed!
    update!(status: 'dismissed')
  end

  def duration_minutes
    return 0 unless session_start && session_end

    ((session_end - session_start) / 60.0).round(1)
  end

  def add_tabs!(page_visit_ids)
    page_visit_ids.each_with_index do |pv_id, index|
      pv = PageVisit.find_by(id: pv_id)
      next unless pv

      research_session_tabs.create!(
        page_visit_id: pv_id,
        url: pv.url,
        title: pv.title,
        domain: pv.domain,
        tab_order: index + 1
      )
    end

    update!(tab_count: research_session_tabs.count)
  end

  def tabs_for_restoration
    research_session_tabs
      .order(:tab_order)
      .map { |tab| { url: tab.url, title: tab.title, order: tab.tab_order } }
  end

  private

  def session_end_after_start
    return unless session_start && session_end

    errors.add(:session_end, 'must be after session start') if session_end <= session_start
  end

  def set_defaults
    self.status ||= 'detected'
    self.restore_count ||= 0
  end
end
```

---

### 3. ResearchSessionTab

**File:** `app/models/research_session_tab.rb`

```ruby
# frozen_string_literal: true

class ResearchSessionTab < ApplicationRecord
  # Associations
  belongs_to :research_session
  belongs_to :page_visit, foreign_key: 'page_visit_id', primary_key: 'id'

  # Validations
  validates :url, presence: true
  validates :page_visit_id, presence: true

  # Scopes
  scope :ordered, -> { order(:tab_order) }

  # Callbacks
  before_validation :populate_from_page_visit, if: -> { page_visit.present? }

  private

  def populate_from_page_visit
    self.url ||= page_visit.url
    self.title ||= page_visit.title
    self.domain ||= page_visit.domain
  end
end
```

---

### 4. ResourcePatternPreference

**File:** `app/models/resource_pattern_preference.rb`

```ruby
# frozen_string_literal: true

class ResourcePatternPreference < ApplicationRecord
  # Associations
  belongs_to :user

  # Validations
  validates :user_id, uniqueness: true
  validates :hoarder_min_duration_seconds, numericality: { greater_than: 0 }, allow_nil: true
  validates :hoarder_max_engagement_rate, numericality: { greater_than: 0, less_than: 1 }, allow_nil: true
  validates :notification_frequency, inclusion: { in: %w[realtime daily weekly never] }, allow_nil: true

  # Callbacks
  after_initialize :set_defaults, if: :new_record?

  private

  def set_defaults
    self.hoarder_detection_enabled = true if hoarder_detection_enabled.nil?
    self.hoarder_min_duration_seconds ||= 300
    self.hoarder_max_engagement_rate ||= 0.05
    self.serial_opener_detection_enabled = true if serial_opener_detection_enabled.nil?
    self.serial_opener_min_opens ||= 3
    self.serial_opener_max_duration_seconds ||= 120
    self.serial_opener_lookback_days ||= 30
    self.research_session_detection_enabled = true if research_session_detection_enabled.nil?
    self.research_session_min_tabs ||= 5
    self.research_session_time_window_minutes ||= 10
    self.notifications_enabled = true if notifications_enabled.nil?
    self.notification_frequency ||= 'daily'
    self.excluded_domains ||= []
  end
end
```

---

## Controllers

### 1. PatternsController

**File:** `app/controllers/api/v1/patterns_controller.rb`

```ruby
# frozen_string_literal: true

module Api
  module V1
    class PatternsController < AuthenticatedController
      # GET /api/v1/patterns/hoarder-tabs
      def hoarder_tabs
        detector = Patterns::HoarderDetector.new(current_user, hoarder_params)
        results = detector.call

        render_json_response(
          success: true,
          data: {
            hoarder_tabs: results,
            total_count: results.size,
            pagination: pagination_meta(results.size, hoarder_params[:limit], hoarder_params[:offset])
          }
        )
      end

      # GET /api/v1/patterns/serial-openers
      def serial_openers
        detector = Patterns::SerialOpenerDetector.new(current_user, serial_opener_params)
        results = detector.call

        render_json_response(
          success: true,
          data: {
            serial_openers: results,
            total_count: results.size,
            pagination: pagination_meta(results.size, serial_opener_params[:limit], serial_opener_params[:offset])
          }
        )
      end

      # GET /api/v1/patterns/research-sessions
      def research_sessions
        detector = Patterns::ResearchSessionDetector.new(current_user, research_session_params)
        results = detector.call

        render_json_response(
          success: true,
          data: {
            research_sessions: results,
            total_count: results.size,
            pagination: pagination_meta(results.size, research_session_params[:limit], research_session_params[:offset])
          }
        )
      end

      private

      def hoarder_params
        {
          min_duration: params[:min_duration]&.to_i || 300,
          max_engagement: params[:max_engagement]&.to_f || 0.05,
          limit: [params[:limit]&.to_i || 50, 100].min,
          offset: params[:offset]&.to_i || 0
        }
      end

      def serial_opener_params
        {
          min_opens: params[:min_opens]&.to_i || 3,
          max_duration: params[:max_duration]&.to_i || 120,
          lookback_days: params[:lookback_days]&.to_i || 30,
          limit: [params[:limit]&.to_i || 50, 100].min,
          offset: params[:offset]&.to_i || 0
        }
      end

      def research_session_params
        {
          min_tabs: params[:min_tabs]&.to_i || 5,
          time_window_min: params[:time_window_min]&.to_i || 10,
          lookback_days: params[:lookback_days]&.to_i || 7,
          limit: [params[:limit]&.to_i || 50, 100].min,
          offset: params[:offset]&.to_i || 0
        }
      end

      def pagination_meta(count, limit, offset)
        {
          limit: limit,
          offset: offset,
          has_more: count >= limit
        }
      end
    end
  end
end
```

---

### 2. ReadingListController

**File:** `app/controllers/api/v1/reading_list_controller.rb`

```ruby
# frozen_string_literal: true

module Api
  module V1
    class ReadingListController < AuthenticatedController
      before_action :set_reading_list_item, only: %i[update destroy]

      # GET /api/v1/reading-list
      def index
        items = current_user.reading_list_items
                            .yield_self { |scope| apply_filters(scope) }
                            .yield_self { |scope| apply_sorting(scope) }
                            .limit(limit)
                            .offset(offset)

        render_json_response(
          success: true,
          data: {
            items: items.as_json(reading_list_json_options),
            stats: reading_list_stats,
            pagination: pagination_meta(items.size)
          }
        )
      end

      # POST /api/v1/reading-list
      def create
        item = current_user.reading_list_items.new(reading_list_params)

        if item.save
          render_json_response(
            success: true,
            message: 'Added to reading list',
            data: item.as_json(reading_list_json_options),
            status: :created
          )
        else
          render_error_response(
            message: 'Failed to add to reading list',
            errors: item.errors.full_messages,
            status: :unprocessable_entity
          )
        end
      end

      # POST /api/v1/reading-list/bulk
      def bulk_create
        results = Patterns::BulkReadingListService.call(
          current_user,
          params[:items],
          skip_duplicates: params[:skip_duplicates]
        )

        render_json_response(
          success: true,
          message: "Added #{results[:created]} items to reading list",
          data: results,
          status: :created
        )
      end

      # PATCH /api/v1/reading-list/:id
      def update
        if @reading_list_item.update(update_reading_list_params)
          render_json_response(
            success: true,
            message: 'Reading list item updated',
            data: @reading_list_item.as_json(reading_list_json_options)
          )
        else
          render_error_response(
            message: 'Failed to update reading list item',
            errors: @reading_list_item.errors.full_messages,
            status: :unprocessable_entity
          )
        end
      end

      # DELETE /api/v1/reading-list/:id
      def destroy
        @reading_list_item.destroy!
        render_json_response(
          success: true,
          message: 'Removed from reading list'
        )
      end

      private

      def set_reading_list_item
        @reading_list_item = current_user.reading_list_items.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_error_response(
          message: 'Reading list item not found',
          status: :not_found
        )
      end

      def reading_list_params
        params.require(:reading_list_item).permit(
          :url, :title, :domain, :page_visit_id, :added_from,
          :estimated_read_time, :notes, :scheduled_for, tags: []
        )
      end

      def update_reading_list_params
        params.permit(:status, :notes, :scheduled_for, tags: [])
      end

      def apply_filters(scope)
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(added_from: params[:added_from]) if params[:added_from].present?
        scope = scope.scheduled if params[:scheduled] == 'true'
        scope = scope.where('tags && ARRAY[?]::varchar[]', params[:tags].split(',')) if params[:tags].present?
        scope
      end

      def apply_sorting(scope)
        sort_column = params[:sort] || 'added_at'
        sort_order = params[:order]&.downcase == 'asc' ? :asc : :desc
        scope.order(sort_column => sort_order)
      end

      def reading_list_stats
        {
          total_unread: current_user.reading_list_items.unread.count,
          total_reading: current_user.reading_list_items.reading.count,
          total_completed: current_user.reading_list_items.completed.count,
          completion_rate: ReadingListItem.completion_rate(current_user)
        }
      end

      def reading_list_json_options
        {
          only: %i[id url title domain status added_at added_from estimated_read_time
                   notes tags scheduled_for completed_at dismissed_at]
        }
      end

      def limit
        [params[:limit]&.to_i || 50, 100].min
      end

      def offset
        params[:offset]&.to_i || 0
      end

      def pagination_meta(count)
        {
          limit: limit,
          offset: offset,
          total: current_user.reading_list_items.count,
          has_more: count >= limit
        }
      end
    end
  end
end
```

---

### 3. ResearchSessionsController

**File:** `app/controllers/api/v1/research_sessions_controller.rb`

```ruby
# frozen_string_literal: true

module Api
  module V1
    class ResearchSessionsController < AuthenticatedController
      before_action :set_research_session, only: %i[show update destroy save restore]

      # GET /api/v1/research-sessions
      def index
        sessions = current_user.research_sessions
                               .yield_self { |scope| apply_filters(scope) }
                               .yield_self { |scope| apply_sorting(scope) }
                               .limit(limit)
                               .offset(offset)

        render_json_response(
          success: true,
          data: {
            sessions: sessions.as_json(session_list_json_options),
            pagination: pagination_meta(sessions.size)
          }
        )
      end

      # GET /api/v1/research-sessions/:id
      def show
        render_json_response(
          success: true,
          data: @research_session.as_json(session_detail_json_options)
        )
      end

      # POST /api/v1/research-sessions
      def create
        session = current_user.research_sessions.new(create_session_params)

        if session.save
          session.add_tabs!(params[:page_visit_ids]) if params[:page_visit_ids].present?

          render_json_response(
            success: true,
            message: 'Research session created',
            data: session.as_json(session_detail_json_options),
            status: :created
          )
        else
          render_error_response(
            message: 'Failed to create research session',
            errors: session.errors.full_messages,
            status: :unprocessable_entity
          )
        end
      end

      # POST /api/v1/research-sessions/:id/save
      def save
        custom_name = params[:session_name]
        @research_session.update!(session_name: custom_name) if custom_name.present?
        @research_session.mark_saved!

        render_json_response(
          success: true,
          message: 'Research session saved',
          data: {
            id: @research_session.id,
            status: @research_session.status,
            saved_at: @research_session.saved_at
          }
        )
      end

      # POST /api/v1/research-sessions/:id/restore
      def restore
        @research_session.mark_restored!
        tabs = @research_session.tabs_for_restoration

        render_json_response(
          success: true,
          message: 'Research session restored',
          data: {
            id: @research_session.id,
            session_name: @research_session.session_name,
            tab_count: @research_session.tab_count,
            tabs: tabs,
            restore_count: @research_session.restore_count,
            last_restored_at: @research_session.last_restored_at
          }
        )
      end

      # PATCH /api/v1/research-sessions/:id
      def update
        if @research_session.update(update_session_params)
          render_json_response(
            success: true,
            message: 'Research session updated'
          )
        else
          render_error_response(
            message: 'Failed to update research session',
            errors: @research_session.errors.full_messages,
            status: :unprocessable_entity
          )
        end
      end

      # DELETE /api/v1/research-sessions/:id
      def destroy
        @research_session.destroy!
        render_json_response(
          success: true,
          message: 'Research session deleted'
        )
      end

      private

      def set_research_session
        @research_session = current_user.research_sessions.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_error_response(
          message: 'Research session not found',
          status: :not_found
        )
      end

      def create_session_params
        params.permit(:session_name).tap do |p|
          p[:session_start] = Time.current
          p[:session_end] = Time.current
          p[:tab_count] = params[:page_visit_ids]&.size || 0
        end
      end

      def update_session_params
        params.permit(:session_name, :status)
      end

      def apply_filters(scope)
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.by_domain(params[:domain]) if params[:domain].present?
        scope
      end

      def apply_sorting(scope)
        sort_column = params[:sort] || 'session_start'
        sort_order = params[:order]&.downcase == 'asc' ? :asc : :desc
        scope.order(sort_column => sort_order)
      end

      def session_list_json_options
        {
          only: %i[id session_name session_start session_end tab_count primary_domain
                   domains topics status saved_at last_restored_at],
          methods: [:duration_minutes],
          include: {
            research_session_tabs: {
              only: %i[url title],
              limit: 3
            }
          }
        }
      end

      def session_detail_json_options
        {
          only: %i[id session_name session_start session_end tab_count primary_domain
                   domains topics total_duration_seconds avg_engagement_rate status
                   saved_at last_restored_at restore_count],
          methods: [:duration_minutes],
          include: {
            research_session_tabs: {
              only: %i[id page_visit_id url title domain tab_order],
              methods: []
            }
          }
        }
      end

      def limit
        [params[:limit]&.to_i || 50, 100].min
      end

      def offset
        params[:offset]&.to_i || 0
      end

      def pagination_meta(count)
        {
          limit: limit,
          offset: offset,
          total: current_user.research_sessions.count,
          has_more: count >= limit
        }
      end
    end
  end
end
```

---

## Routes

**File:** `config/routes.rb`

```ruby
namespace :api do
  namespace :v1 do
    # Pattern detection endpoints
    get 'patterns/hoarder-tabs', to: 'patterns#hoarder_tabs'
    get 'patterns/serial-openers', to: 'patterns#serial_openers'
    get 'patterns/research-sessions', to: 'patterns#research_sessions'

    # Reading list endpoints
    resources :reading_list, only: %i[index create update destroy], path: 'reading-list' do
      collection do
        post :bulk, to: 'reading_list#bulk_create'
      end
    end

    # Research sessions endpoints
    resources :research_sessions, only: %i[index show create update destroy], path: 'research-sessions' do
      member do
        post :save
        post :restore
      end
    end

    # Preferences endpoints
    resource :pattern_preferences, only: %i[show update], path: 'preferences/pattern-detection'
  end
end
```

---

**Status:** Ready for Implementation
**Last Updated:** 2025-10-16

**Next:** Continue with browser extension, testing, and timeline documents.
