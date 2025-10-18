# What We Actually Need - Simplified Implementation Plan

## What We Already Have ✅

### Existing Data (page_visits + tab_aggregates)
```
✅ duration_seconds - How long tab was open
✅ active_duration_seconds - Time actually engaged
✅ engagement_rate - % active engagement
✅ visited_at - Timestamp
✅ domain - Domain of URL
✅ url, title - Content identification
✅ tab_id - Tab tracking
✅ closed_at (in tab_aggregates) - When tab closed
```

### What We Can Already Detect:

#### 1. Hoarder Tabs 📚
**Query Works Now:**
```sql
SELECT url, title, duration_seconds, engagement_rate
FROM page_visits
WHERE duration_seconds > 300
  AND engagement_rate < 0.05
ORDER BY duration_seconds DESC;
```
**Result:** 14 hoarder tabs found! ✅

---

#### 2. Serial Openers 🔄
**Query Works Now:**
```sql
SELECT
  domain,
  COUNT(*) as times_opened,
  AVG(duration_seconds) as avg_duration
FROM page_visits
WHERE duration_seconds < 120
  AND visited_at > NOW() - INTERVAL '7 days'
GROUP BY domain
HAVING COUNT(*) >= 3
ORDER BY COUNT(*) DESC;
```
**Result:** 52 domains with serial opening pattern! ✅

---

#### 3. Research Sessions 🐇
**Query Works Now:**
```sql
SELECT
  domain,
  DATE_TRUNC('hour', visited_at) as session_time,
  COUNT(*) as tab_count
FROM page_visits
GROUP BY domain, DATE_TRUNC('hour', visited_at)
HAVING COUNT(*) >= 5
ORDER BY session_time DESC;
```
**Result:** 101 research sessions detected! ✅

---

## What We Actually Need to Build

### 1. Reading List / Save for Later

**New Table:**
```sql
CREATE TABLE reading_list_items (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  page_visit_id VARCHAR(255) REFERENCES page_visits(id),
  url TEXT NOT NULL,
  title TEXT,
  domain VARCHAR(255),

  -- Core fields
  added_at TIMESTAMP DEFAULT NOW(),
  added_from VARCHAR(50), -- 'hoarder_detection', 'manual_save', 'serial_opener'
  status VARCHAR(50) DEFAULT 'unread', -- 'unread', 'reading', 'completed', 'dismissed'

  -- Optional fields
  estimated_read_time INTEGER,
  notes TEXT,
  tags TEXT[],
  scheduled_for TIMESTAMP,
  completed_at TIMESTAMP,
  dismissed_at TIMESTAMP,

  UNIQUE(user_id, url) -- Can't save same URL twice
);

CREATE INDEX idx_reading_list_user_status ON reading_list_items(user_id, status);
```

**API Endpoints:**
```
POST   /api/v1/reading-list        # Add item
GET    /api/v1/reading-list        # Get all items
PATCH  /api/v1/reading-list/:id    # Update status
DELETE /api/v1/reading-list/:id    # Remove item
POST   /api/v1/reading-list/bulk   # Bulk add from detection
```

---

### 2. Research Sessions Storage

**New Table:**
```sql
CREATE TABLE research_sessions (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),

  -- Session metadata
  session_name VARCHAR(255) NOT NULL,
  session_start TIMESTAMP NOT NULL,
  session_end TIMESTAMP NOT NULL,

  -- Session stats
  tab_count INTEGER NOT NULL,
  primary_domain VARCHAR(255),
  domains TEXT[],

  -- User actions
  status VARCHAR(50) DEFAULT 'detected', -- 'detected', 'saved', 'restored', 'dismissed'
  saved_at TIMESTAMP,
  last_restored_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Link tabs to session
CREATE TABLE research_session_tabs (
  id BIGSERIAL PRIMARY KEY,
  session_id BIGINT REFERENCES research_sessions(id) ON DELETE CASCADE,
  page_visit_id VARCHAR(255) REFERENCES page_visits(id),
  tab_order INTEGER
);
```

**API Endpoints:**
```
GET  /api/v1/research-sessions           # Get detected sessions
POST /api/v1/research-sessions/:id/save  # Save session
POST /api/v1/research-sessions/:id/restore  # Restore all tabs
```

---

### 3. Pattern Detection API Endpoints

**These query existing data, no new tables needed:**

```
GET /api/v1/patterns/hoarder-tabs
GET /api/v1/patterns/serial-openers
GET /api/v1/patterns/research-sessions
```

**Example Response:**
```json
{
  "success": true,
  "data": {
    "hoarder_tabs": [
      {
        "url": "https://docs.google.com/...",
        "title": "Important Spreadsheet",
        "duration_seconds": 94355,
        "engagement_rate": 0.001,
        "visited_at": "2025-10-13T12:10:38Z",
        "suggestion": "You've had this open for 26 hours but only engaged for 2 minutes. Save for later?"
      }
    ]
  }
}
```

---

### 4. Dashboard / UI

**Browser Extension Popup:**
```
┌─────────────────────────────────────┐
│  HeyHo - Smart Resource Manager    │
├─────────────────────────────────────┤
│  📚 Hoarder Tabs              [14]  │
│  → Save to reading list             │
│                                     │
│  🔄 Serial Openers            [52]  │
│  → Pin or schedule reading          │
│                                     │
│  🐇 Research Sessions        [101]  │
│  → Save or restore sessions         │
└─────────────────────────────────────┘
```

**Web Dashboard:**
- Reading list view
- Research sessions archive
- Pattern insights and stats

---

## What We DON'T Need (For MVP)

### ❌ Session Tracking System
**Why:** `tab_aggregates.closed_at` already tells us when tabs closed. We can calculate if tabs are "still open" by checking if there's no `closed_at` or if the tab has recent `page_visits`.

**Simple Check:**
```sql
-- Find currently open tabs (no closed_at in tab_aggregates)
SELECT pv.*
FROM page_visits pv
LEFT JOIN tab_aggregates ta ON ta.page_visit_id = pv.id
WHERE ta.closed_at IS NULL
  OR pv.visited_at > NOW() - INTERVAL '1 hour';
```

---

### ❌ Cross-Session Correlation
**Why:** For MVP, we don't need to track if it's the "same" tab across restarts. We just need to know:
- Tab was open for X time with low engagement → Hoarder tab
- Same URL opened multiple times → Serial opener

We can add session tracking later if users actually need "restore from last session" functionality.

---

### ❌ Tab Fingerprinting
**Why:** Not needed for pattern detection. We already have `url`, `domain`, `tab_id`.

---

### ❌ URL Normalization (For MVP)
**Why:** Nice to have, but not critical. We can add this later if we see users with duplicate URLs due to tracking params.

**Simple Fix:** Just group by `domain` for serial opener detection instead of exact URL.

---

### ❌ Complex Scheduled Reading
**Why:** For MVP, just save to reading list. Don't need calendar integration yet.

**Simple Alternative:** Add a `scheduled_for` field and show reminders in the extension.

---

### ❌ Smart Scheduling Algorithm
**Why:** Too complex for MVP. For now, just let users manually schedule or mark as "read later".

**Future Enhancement:** Learn user patterns and suggest best reading times.

---

## Simplified MVP Implementation Plan

### Phase 1: Detection APIs (Week 1)
**Goal:** Expose pattern detection via API

**Tasks:**
- [ ] Create `/api/v1/patterns/hoarder-tabs` endpoint
- [ ] Create `/api/v1/patterns/serial-openers` endpoint
- [ ] Create `/api/v1/patterns/research-sessions` endpoint
- [ ] Write RSpec tests for detection queries
- [ ] Add pagination and filtering

**Estimated:** 2-3 days

---

### Phase 2: Reading List (Week 1-2)
**Goal:** Save resources for later

**Tasks:**
- [ ] Create `reading_list_items` table migration
- [ ] Create `ReadingListItem` model with validations
- [ ] Create CRUD API endpoints for reading list
- [ ] Add bulk-add endpoint for detected patterns
- [ ] Write RSpec tests
- [ ] Add to Postman collection

**Estimated:** 3-4 days

---

### Phase 3: Research Sessions (Week 2)
**Goal:** Save and restore browsing sessions

**Tasks:**
- [ ] Create `research_sessions` and `research_session_tabs` tables
- [ ] Create `ResearchSession` model
- [ ] Create detection service (group tabs into sessions)
- [ ] Create API endpoints (list, save, restore)
- [ ] Write RSpec tests

**Estimated:** 3-4 days

---

### Phase 4: Browser Extension UI (Week 3)
**Goal:** Display patterns and allow actions

**Tasks:**
- [ ] Design extension popup UI
- [ ] Show pattern counts (hoarder tabs, serial openers, sessions)
- [ ] Add "Save to reading list" action
- [ ] Add "Save session" action
- [ ] Add "Restore session" functionality
- [ ] Connect to APIs

**Estimated:** 4-5 days

---

### Phase 5: Web Dashboard (Week 3-4)
**Goal:** Full-featured UI for managing resources

**Tasks:**
- [ ] Design reading list page
- [ ] Design research sessions archive
- [ ] Add filtering and search
- [ ] Show pattern insights/stats
- [ ] Mark items as read/completed
- [ ] Delete/dismiss items

**Estimated:** 5-7 days

---

## SQL Queries We'll Use (Already Working!)

### 1. Hoarder Tabs Detection
```sql
SELECT
  pv.id,
  pv.url,
  pv.title,
  pv.domain,
  pv.duration_seconds,
  pv.engagement_rate,
  pv.visited_at,
  ROUND(pv.duration_seconds / 3600.0, 1) as hours_open
FROM page_visits pv
WHERE pv.user_id = :user_id
  AND pv.duration_seconds > 300
  AND pv.engagement_rate < 0.05
ORDER BY pv.duration_seconds DESC
LIMIT 50;
```

---

### 2. Serial Openers Detection
```sql
WITH domain_opens AS (
  SELECT
    domain,
    COUNT(*) as open_count,
    AVG(duration_seconds) as avg_duration,
    MAX(visited_at) as last_opened,
    ARRAY_AGG(id ORDER BY visited_at DESC) as visit_ids
  FROM page_visits
  WHERE user_id = :user_id
    AND duration_seconds < 120
    AND visited_at > NOW() - INTERVAL '30 days'
  GROUP BY domain
  HAVING COUNT(*) >= 3
)
SELECT
  domain,
  open_count,
  ROUND(avg_duration, 1) as avg_seconds,
  last_opened,
  visit_ids[1:5] as recent_visit_ids -- Get 5 most recent
FROM domain_opens
ORDER BY open_count DESC;
```

---

### 3. Research Sessions Detection
```sql
WITH tab_bursts AS (
  SELECT
    domain,
    visited_at,
    LAG(visited_at) OVER (PARTITION BY domain ORDER BY visited_at) as prev_visit,
    id as page_visit_id
  FROM page_visits
  WHERE user_id = :user_id
    AND visited_at > NOW() - INTERVAL '7 days'
),
grouped_sessions AS (
  SELECT
    domain,
    DATE_TRUNC('hour', visited_at) as session_hour,
    COUNT(*) as tab_count,
    MIN(visited_at) as session_start,
    MAX(visited_at) as session_end,
    ARRAY_AGG(page_visit_id ORDER BY visited_at) as tab_ids
  FROM tab_bursts
  WHERE (visited_at - prev_visit) < INTERVAL '10 minutes'
    OR prev_visit IS NULL
  GROUP BY domain, DATE_TRUNC('hour', visited_at)
  HAVING COUNT(*) >= 5
)
SELECT
  domain,
  tab_count,
  session_start,
  session_end,
  EXTRACT(EPOCH FROM (session_end - session_start)) / 60 as duration_minutes,
  tab_ids
FROM grouped_sessions
ORDER BY session_start DESC;
```

---

## Summary: What We Actually Need to Build

### Database (New)
1. `reading_list_items` table
2. `research_sessions` table
3. `research_session_tabs` join table

### Backend (New)
1. Pattern detection API endpoints (just wrap existing queries)
2. Reading list CRUD endpoints
3. Research session CRUD endpoints
4. Detection service for grouping sessions

### Frontend (New)
1. Browser extension popup showing patterns
2. Web dashboard for reading list
3. Research sessions archive page

### What We DON'T Need (Yet)
- ❌ Session tracking system
- ❌ Tab heartbeat from extension
- ❌ Cross-session correlation
- ❌ URL normalization
- ❌ Smart scheduling algorithms
- ❌ Calendar integration

---

## Total Estimate: 3-4 Weeks

**Week 1:** Detection APIs + Reading List backend
**Week 2:** Research Sessions backend
**Week 3:** Browser Extension UI
**Week 4:** Web Dashboard + Polish

---

**Next Steps:**
1. Start with detection API endpoints (easiest, uses existing data)
2. Test queries with real data
3. Build reading list feature
4. Add research sessions
5. Connect browser extension

Much simpler than the original plan! 🎉
