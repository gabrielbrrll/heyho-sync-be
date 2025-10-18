# Phase 3: Database Schema

## Overview

This document outlines all database migrations and schema changes needed for Phase 3 features.

---

## Migration 1: Reading List Items

**Purpose:** Store resources that users want to read later

**Migration File:** `db/migrate/YYYYMMDDHHMMSS_create_reading_list_items.rb`

```ruby
# frozen_string_literal: true

class CreateReadingListItems < ActiveRecord::Migration[7.0]
  def change
    create_table :reading_list_items, id: :bigserial do |t|
      # Associations
      t.references :user, null: false, foreign_key: true, index: true
      t.string :page_visit_id, null: true

      # Core fields
      t.text :url, null: false
      t.string :title
      t.string :domain

      # Metadata
      t.timestamp :added_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.string :added_from, limit: 50 # 'hoarder_detection', 'manual_save', 'serial_opener', 'research_session'
      t.string :status, limit: 50, default: 'unread', null: false # 'unread', 'reading', 'completed', 'dismissed'

      # Optional fields
      t.integer :estimated_read_time # seconds
      t.text :notes
      t.string :tags, array: true, default: []
      t.timestamp :scheduled_for
      t.timestamp :completed_at
      t.timestamp :dismissed_at

      t.timestamps
    end

    # Foreign key to page_visits (if exists)
    add_foreign_key :reading_list_items, :page_visits, column: :page_visit_id, primary_key: :id, on_delete: :nullify

    # Indexes
    add_index :reading_list_items, [:user_id, :status], name: 'idx_reading_list_user_status'
    add_index :reading_list_items, :scheduled_for, where: "status = 'unread'", name: 'idx_reading_list_scheduled'
    add_index :reading_list_items, :added_at, name: 'idx_reading_list_added_at'

    # Unique constraint: can't save same URL twice per user
    add_index :reading_list_items, [:user_id, :url], unique: true, name: 'idx_reading_list_user_url_unique'
  end
end
```

### Expected Schema

```sql
Table "public.reading_list_items"
       Column        |            Type             | Default
---------------------+-----------------------------+---------
 id                  | bigint                      | nextval
 user_id             | bigint                      | NOT NULL
 page_visit_id       | character varying           |
 url                 | text                        | NOT NULL
 title               | character varying           |
 domain              | character varying           |
 added_at            | timestamp without time zone | NOW()
 added_from          | character varying(50)       |
 status              | character varying(50)       | 'unread'
 estimated_read_time | integer                     |
 notes               | text                        |
 tags                | character varying[]         | []
 scheduled_for       | timestamp without time zone |
 completed_at        | timestamp without time zone |
 dismissed_at        | timestamp without time zone |
 created_at          | timestamp without time zone | NOT NULL
 updated_at          | timestamp without time zone | NOT NULL

Indexes:
  "reading_list_items_pkey" PRIMARY KEY (id)
  "idx_reading_list_user_url_unique" UNIQUE (user_id, url)
  "idx_reading_list_user_status" (user_id, status)
  "idx_reading_list_scheduled" (scheduled_for) WHERE status = 'unread'
  "idx_reading_list_added_at" (added_at)
```

---

## Migration 2: Research Sessions

**Purpose:** Store detected browsing sessions for later restoration

**Migration File:** `db/migrate/YYYYMMDDHHMMSS_create_research_sessions.rb`

```ruby
# frozen_string_literal: true

class CreateResearchSessions < ActiveRecord::Migration[7.0]
  def change
    create_table :research_sessions, id: :bigserial do |t|
      # Associations
      t.references :user, null: false, foreign_key: true, index: true

      # Session metadata
      t.string :session_name, null: false
      t.timestamp :session_start, null: false
      t.timestamp :session_end, null: false

      # Session stats
      t.integer :tab_count, null: false
      t.string :primary_domain
      t.string :domains, array: true, default: []
      t.string :topics, array: true, default: [] # Extracted keywords

      # Aggregated engagement
      t.integer :total_duration_seconds
      t.float :avg_engagement_rate

      # User actions
      t.string :status, limit: 50, default: 'detected', null: false # 'detected', 'saved', 'restored', 'dismissed'
      t.timestamp :saved_at
      t.timestamp :last_restored_at
      t.integer :restore_count, default: 0

      t.timestamps
    end

    # Indexes
    add_index :research_sessions, [:user_id, :status], name: 'idx_research_sessions_user_status'
    add_index :research_sessions, :session_start, name: 'idx_research_sessions_start'
    add_index :research_sessions, :primary_domain, name: 'idx_research_sessions_domain'
  end
end
```

### Expected Schema

```sql
Table "public.research_sessions"
         Column         |            Type             | Default
------------------------+-----------------------------+---------
 id                     | bigint                      | nextval
 user_id                | bigint                      | NOT NULL
 session_name           | character varying           | NOT NULL
 session_start          | timestamp without time zone | NOT NULL
 session_end            | timestamp without time zone | NOT NULL
 tab_count              | integer                     | NOT NULL
 primary_domain         | character varying           |
 domains                | character varying[]         | []
 topics                 | character varying[]         | []
 total_duration_seconds | integer                     |
 avg_engagement_rate    | double precision            |
 status                 | character varying(50)       | 'detected'
 saved_at               | timestamp without time zone |
 last_restored_at       | timestamp without time zone |
 restore_count          | integer                     | 0
 created_at             | timestamp without time zone | NOT NULL
 updated_at             | timestamp without time zone | NOT NULL

Indexes:
  "research_sessions_pkey" PRIMARY KEY (id)
  "idx_research_sessions_user_status" (user_id, status)
  "idx_research_sessions_start" (session_start)
  "idx_research_sessions_domain" (primary_domain)
```

---

## Migration 3: Research Session Tabs (Join Table)

**Purpose:** Link page visits to research sessions

**Migration File:** `db/migrate/YYYYMMDDHHMMSS_create_research_session_tabs.rb`

```ruby
# frozen_string_literal: true

class CreateResearchSessionTabs < ActiveRecord::Migration[7.0]
  def change
    create_table :research_session_tabs, id: :bigserial do |t|
      # Associations
      t.references :research_session, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :page_visit_id, null: false

      # Tab metadata
      t.integer :tab_order # Order in which tabs were opened
      t.string :url, null: false
      t.string :title
      t.string :domain

      t.timestamps
    end

    # Foreign key to page_visits
    add_foreign_key :research_session_tabs, :page_visits, column: :page_visit_id, primary_key: :id, on_delete: :cascade

    # Indexes
    add_index :research_session_tabs, :page_visit_id, name: 'idx_session_tabs_page_visit'
    add_index :research_session_tabs, [:research_session_id, :tab_order], name: 'idx_session_tabs_order'
  end
end
```

### Expected Schema

```sql
Table "public.research_session_tabs"
       Column         |       Type        | Default
----------------------+-------------------+---------
 id                   | bigint            | nextval
 research_session_id  | bigint            | NOT NULL
 page_visit_id        | character varying | NOT NULL
 tab_order            | integer           |
 url                  | character varying | NOT NULL
 title                | character varying |
 domain               | character varying |
 created_at           | timestamp         | NOT NULL
 updated_at           | timestamp         | NOT NULL

Indexes:
  "research_session_tabs_pkey" PRIMARY KEY (id)
  "idx_session_tabs_page_visit" (page_visit_id)
  "idx_session_tabs_order" (research_session_id, tab_order)

Foreign Keys:
  "fk_research_session_tabs_session" FOREIGN KEY (research_session_id)
    REFERENCES research_sessions(id) ON DELETE CASCADE
  "fk_research_session_tabs_page_visit" FOREIGN KEY (page_visit_id)
    REFERENCES page_visits(id) ON DELETE CASCADE
```

---

## Migration 4: User Preferences (Optional)

**Purpose:** Store user preferences for pattern detection

**Migration File:** `db/migrate/YYYYMMDDHHMMSS_create_resource_pattern_preferences.rb`

```ruby
# frozen_string_literal: true

class CreateResourcePatternPreferences < ActiveRecord::Migration[7.0]
  def change
    create_table :resource_pattern_preferences, id: :bigserial do |t|
      # One preference record per user
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      # Hoarder tab settings
      t.boolean :hoarder_detection_enabled, default: true
      t.integer :hoarder_min_duration_seconds, default: 300 # 5 minutes
      t.float :hoarder_max_engagement_rate, default: 0.05 # 5%

      # Serial opener settings
      t.boolean :serial_opener_detection_enabled, default: true
      t.integer :serial_opener_min_opens, default: 3
      t.integer :serial_opener_max_duration_seconds, default: 120 # 2 minutes
      t.integer :serial_opener_lookback_days, default: 30

      # Research session settings
      t.boolean :research_session_detection_enabled, default: true
      t.integer :research_session_min_tabs, default: 5
      t.integer :research_session_time_window_minutes, default: 10

      # Notification settings
      t.boolean :notifications_enabled, default: true
      t.string :notification_frequency, default: 'daily' # 'realtime', 'daily', 'weekly', 'never'
      t.integer :digest_day_of_week, default: 0 # 0 = Sunday
      t.time :digest_time, default: '09:00:00'

      # Privacy settings
      t.string :excluded_domains, array: true, default: []

      t.timestamps
    end
  end
end
```

---

## Data Validation

### Reading List Items
```ruby
# Model validations
validates :url, presence: true, uniqueness: { scope: :user_id }
validates :status, inclusion: { in: %w[unread reading completed dismissed] }
validates :added_from, inclusion: {
  in: %w[hoarder_detection manual_save serial_opener research_session api_import],
  allow_nil: true
}
```

### Research Sessions
```ruby
# Model validations
validates :session_name, presence: true
validates :session_start, presence: true
validates :session_end, presence: true
validates :tab_count, presence: true, numericality: { greater_than: 0 }
validates :status, inclusion: { in: %w[detected saved restored dismissed] }
validate :session_end_after_start

def session_end_after_start
  return unless session_start && session_end
  errors.add(:session_end, "must be after session start") if session_end <= session_start
end
```

---

## Index Performance Considerations

### Expected Query Patterns

1. **Reading List Queries:**
   ```sql
   -- Most common: Get unread items for user
   WHERE user_id = X AND status = 'unread'
   -- Index: idx_reading_list_user_status (covers this)

   -- Common: Get scheduled items
   WHERE status = 'unread' AND scheduled_for <= NOW()
   -- Index: idx_reading_list_scheduled (partial index)
   ```

2. **Research Session Queries:**
   ```sql
   -- Most common: Get recent sessions for user
   WHERE user_id = X ORDER BY session_start DESC
   -- Index: idx_research_sessions_user_status + idx_research_sessions_start

   -- Common: Get sessions by domain
   WHERE user_id = X AND primary_domain = 'github.com'
   -- Index: idx_research_sessions_domain
   ```

3. **Session Tabs Queries:**
   ```sql
   -- Most common: Get tabs for a session in order
   WHERE research_session_id = X ORDER BY tab_order
   -- Index: idx_session_tabs_order (covers this)
   ```

### Index Maintenance

All indexes are **B-tree** by default (PostgreSQL default).

For large datasets (> 1M records), consider:
- VACUUM ANALYZE after bulk imports
- REINDEX if query performance degrades
- Monitor with `pg_stat_user_indexes`

---

## Migration Rollback

Each migration includes implicit `down` via `change` method.

Manual rollback if needed:
```bash
rails db:rollback STEP=1  # Rollback last migration
rails db:rollback STEP=3  # Rollback last 3 migrations
```

---

## Testing Migrations

### Run migrations:
```bash
# Development
rails db:migrate

# Test database
RAILS_ENV=test rails db:migrate

# Check status
rails db:migrate:status
```

### Verify schema:
```bash
# Connect to PostgreSQL
docker-compose exec sync-api rails dbconsole

# Check tables
\dt reading_list_items
\dt research_sessions
\dt research_session_tabs

# Check indexes
\di reading_list_items
```

### Seed test data:
```ruby
# db/seeds.rb or spec/factories
user = User.first

# Create reading list item
ReadingListItem.create!(
  user: user,
  url: 'https://example.com/article',
  title: 'Test Article',
  domain: 'example.com',
  added_from: 'manual_save',
  status: 'unread'
)

# Create research session
session = ResearchSession.create!(
  user: user,
  session_name: 'React Testing Research',
  session_start: 1.hour.ago,
  session_end: Time.current,
  tab_count: 5,
  primary_domain: 'stackoverflow.com',
  domains: ['stackoverflow.com', 'github.com'],
  status: 'detected'
)
```

---

## Schema Diagram

```
┌─────────────────┐
│     users       │
└────────┬────────┘
         │
         │ 1:N
         │
    ┌────┴──────────────────┬─────────────────────┐
    │                       │                     │
    │                       │                     │
┌───▼──────────────────┐ ┌──▼──────────────────┐ │
│ reading_list_items   │ │ research_sessions   │ │
└──────────────────────┘ └──────┬──────────────┘ │
                                │                 │
                                │ 1:N             │
                                │                 │
                     ┌──────────▼─────────────┐   │
                     │ research_session_tabs  │   │
                     └────────────────────────┘   │
                                                  │
                                                  │ N:1
                                            ┌─────▼─────────┐
                                            │ page_visits   │
                                            └───────────────┘
```

---

## Data Size Estimates

### Reading List Items
- **Avg record size:** ~500 bytes
- **Expected records per user:** 50-200
- **1000 users:** 50K-200K records = 25-100 MB

### Research Sessions
- **Avg record size:** ~300 bytes
- **Expected sessions per user:** 20-100
- **1000 users:** 20K-100K records = 6-30 MB

### Research Session Tabs
- **Avg record size:** ~200 bytes
- **Expected tabs per session:** 5-15
- **Linked to 50K sessions:** 250K-750K records = 50-150 MB

**Total additional storage:** ~100-300 MB for 1000 users

---

## Next Steps

1. Review migrations with team
2. Run migrations in development
3. Verify indexes are created
4. Seed test data
5. Proceed to `02-api-endpoints.md`

---

**Status:** Ready for Implementation
**Last Updated:** 2025-10-16
