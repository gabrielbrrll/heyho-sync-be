# Phase Priority: Resource Pattern Detection

**Focus:** Detecting user browsing patterns to identify resource management needs

**Priority Features:**
1. The Hoarder's Stack 📚 - Tabs kept open but unread
2. Serial Openers 🔄 - Repeatedly opening same resources  
3. Research Rabbit Holes 🐇 - Deep dives on topics

---

## Feature 1: The Hoarder's Stack 📚

### Goal
Identify tabs/resources that users keep open with intent to read but never actually engage with.

### Detection Logic
```
duration_seconds > 300 (5+ minutes open)
AND engagement_rate < 0.05 (less than 5% active engagement)
AND still_open_across_sessions = true
```

### What We Need to Prepare

#### 1. Session Tracking System
**Problem:** We need to know if a tab is "still open" across browser sessions.

**Current State:**
- We track `page_visits` with `visited_at` and duration
- We have `tab_id` for tracking individual tabs
- We DON'T track when tabs are closed vs. kept open

**What to Build:**
```sql
-- Add session tracking
ALTER TABLE page_visits ADD COLUMN session_id VARCHAR(255);
ALTER TABLE page_visits ADD COLUMN is_currently_open BOOLEAN DEFAULT false;
ALTER TABLE page_visits ADD COLUMN last_seen_at TIMESTAMP;
ALTER TABLE page_visits ADD COLUMN close_reason VARCHAR(50); -- 'user_closed', 'session_ended', 'still_open'
```

**Browser Extension Changes:**
- Track when tabs remain open across browser restarts
- Send heartbeat for "still open" tabs every 5 minutes
- Detect tab close events vs. browser close events

**API Endpoint Needed:**
```
POST /api/v1/tab-sessions/heartbeat
Body: {
  tab_id: "1234",
  page_visit_id: "pv_xxx",
  session_id: "session_abc",
  is_open: true,
  timestamp: "2025-10-16T21:00:00Z"
}
```

---

#### 2. Cross-Session Correlation
**Problem:** Identify the SAME tab across browser restarts.

**Challenge:**
- Browser assigns new tab IDs on restart
- We need to correlate: Same URL + reopened quickly after session end = same "intent tab"

**Solution - Tab Fingerprinting:**
```javascript
// In browser extension
const tabFingerprint = {
  url: tab.url,
  title: tab.title,
  domain: extractDomain(tab.url),
  window_id: tab.windowId,
  index: tab.index, // position in tab bar
  last_session_id: previousSessionId
};
```

**API Logic:**
```sql
-- Find potential "same tab" from previous session
SELECT * FROM page_visits
WHERE url = :url
  AND user_id = :user_id
  AND close_reason = 'session_ended'
  AND visited_at > NOW() - INTERVAL '1 hour'
ORDER BY visited_at DESC
LIMIT 1;

-- If found, link as "continued tab"
UPDATE page_visits
SET continued_from_visit_id = :previous_visit_id,
    session_count = session_count + 1
WHERE id = :current_visit_id;
```

**New Table:**
```sql
CREATE TABLE tab_sessions (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  session_id VARCHAR(255) UNIQUE NOT NULL,
  started_at TIMESTAMP NOT NULL,
  ended_at TIMESTAMP,
  browser_close_reason VARCHAR(50), -- 'user_quit', 'crash', 'restart', 'still_active'
  tab_count INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_tab_sessions_user_id ON tab_sessions(user_id);
CREATE INDEX idx_tab_sessions_session_id ON tab_sessions(session_id);
```

---

#### 3. Hoarder Detection Query
**Once we have session tracking:**

```sql
-- Find hoarder tabs for a user
SELECT
  pv.id,
  pv.url,
  pv.title,
  pv.domain,
  pv.visited_at,
  pv.duration_seconds,
  pv.engagement_rate,
  pv.session_count,
  pv.last_seen_at,
  EXTRACT(EPOCH FROM (NOW() - pv.visited_at)) / 86400 as days_open
FROM page_visits pv
WHERE pv.user_id = :user_id
  AND pv.is_currently_open = true
  AND pv.duration_seconds > 300
  AND pv.engagement_rate < 0.05
  AND pv.session_count >= 2  -- Still open after 2+ sessions
ORDER BY pv.visited_at ASC
LIMIT 20;
```

---

#### 4. User Actions & Reading List
**What users can do with hoarder tabs:**

**Reading List Table:**
```sql
CREATE TABLE reading_list_items (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  page_visit_id VARCHAR(255) REFERENCES page_visits(id),
  url TEXT NOT NULL,
  title TEXT,
  domain VARCHAR(255),
  added_at TIMESTAMP DEFAULT NOW(),
  added_from VARCHAR(50), -- 'hoarder_detection', 'manual_save', 'zombie_recovery'
  status VARCHAR(50) DEFAULT 'unread', -- 'unread', 'reading', 'completed', 'dismissed'
  estimated_read_time INTEGER, -- seconds
  notes TEXT,
  tags TEXT[], -- user-defined tags
  scheduled_for TIMESTAMP, -- when to remind user
  completed_at TIMESTAMP,
  dismissed_at TIMESTAMP
);

CREATE INDEX idx_reading_list_user_status ON reading_list_items(user_id, status);
CREATE INDEX idx_reading_list_scheduled ON reading_list_items(scheduled_for) WHERE status = 'unread';
```

**API Endpoints:**
```
POST   /api/v1/reading-list/items          # Add to reading list
GET    /api/v1/reading-list/items          # Get reading list
PATCH  /api/v1/reading-list/items/:id      # Update status/notes
DELETE /api/v1/reading-list/items/:id      # Remove from list
POST   /api/v1/reading-list/bulk-add       # Bulk add hoarder tabs
```

---

#### 5. Notification System
**How to alert users about hoarder tabs:**

**Options:**
1. **In-App Badge** - "You have 12 tabs saved for later"
2. **Browser Extension Popup** - Show count in extension icon
3. **Weekly Digest** - Email summary
4. **Smart Prompt** - "You have 3 tabs open for 5+ days. Want to save them?"

**Notification Rules:**
```sql
CREATE TABLE user_notification_preferences (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) UNIQUE,
  hoarder_alert_enabled BOOLEAN DEFAULT true,
  hoarder_alert_threshold INTEGER DEFAULT 5, -- alert after 5 hoarder tabs
  hoarder_alert_frequency VARCHAR(20) DEFAULT 'daily', -- 'realtime', 'daily', 'weekly'
  digest_day_of_week INTEGER DEFAULT 0, -- 0 = Sunday
  digest_time TIME DEFAULT '09:00:00',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

---

## Feature 2: Serial Openers 🔄

### Goal
Detect when users repeatedly open the same resource but never finish reading it.

### Detection Logic
```sql
SELECT domain, url, COUNT(*) as open_count
FROM page_visits
WHERE user_id = :user_id
  AND duration_seconds < 120  -- Each visit < 2min
  AND visited_at > NOW() - INTERVAL '7 days'
GROUP BY domain, url
HAVING COUNT(*) >= 3
ORDER BY COUNT(*) DESC;
```

### What We Need to Prepare

#### 1. URL Normalization
**Problem:** Same article might have different URLs.

**Examples:**
```
https://medium.com/article?source=email
https://medium.com/article?utm_source=twitter
https://medium.com/article
```

**Solution - Canonical URL:**
```javascript
// In browser extension
function normalizeURL(url) {
  const parsed = new URL(url);

  // Remove tracking params
  const trackingParams = ['utm_source', 'utm_medium', 'utm_campaign', 'source', 'ref'];
  trackingParams.forEach(param => parsed.searchParams.delete(param));

  // Remove trailing slashes
  parsed.pathname = parsed.pathname.replace(/\/+$/, '');

  return parsed.toString();
}
```

**Database:**
```sql
ALTER TABLE page_visits ADD COLUMN canonical_url TEXT;
CREATE INDEX idx_page_visits_canonical_url ON page_visits(canonical_url);
```

---

#### 2. Serial Opener Detection Query
```sql
-- Find resources user keeps opening but not reading
WITH serial_opens AS (
  SELECT
    canonical_url,
    url, -- keep original for display
    title,
    domain,
    COUNT(*) as open_count,
    AVG(duration_seconds) as avg_duration,
    MAX(visited_at) as last_opened,
    MIN(visited_at) as first_opened,
    ARRAY_AGG(id ORDER BY visited_at DESC) as visit_ids
  FROM page_visits
  WHERE user_id = :user_id
    AND visited_at > NOW() - INTERVAL '30 days'
  GROUP BY canonical_url, url, title, domain
  HAVING COUNT(*) >= 3
    AND AVG(duration_seconds) < 120
)
SELECT
  *,
  EXTRACT(EPOCH FROM (last_opened - first_opened)) / 86400 as days_between_first_last
FROM serial_opens
ORDER BY open_count DESC, last_opened DESC;
```

---

#### 3. Action: Pin or Schedule
**When we detect serial openers, offer actions:**

**Pinned Resources Table:**
```sql
CREATE TABLE pinned_resources (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  canonical_url TEXT NOT NULL,
  url TEXT NOT NULL,
  title TEXT,
  domain VARCHAR(255),
  pinned_at TIMESTAMP DEFAULT NOW(),
  pin_reason VARCHAR(100), -- 'serial_opener', 'user_manual', 'important'
  pin_location VARCHAR(50) DEFAULT 'sidebar', -- 'sidebar', 'new_tab', 'extension_popup'
  notes TEXT,
  reminder_enabled BOOLEAN DEFAULT false,
  reminder_frequency VARCHAR(20), -- 'daily', 'weekly', 'monthly'
  last_reminded_at TIMESTAMP,
  unpinned_at TIMESTAMP,
  UNIQUE(user_id, canonical_url)
);

CREATE INDEX idx_pinned_user_active ON pinned_resources(user_id) WHERE unpinned_at IS NULL;
```

**Scheduled Reading Table:**
```sql
CREATE TABLE scheduled_reading (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  page_visit_id VARCHAR(255) REFERENCES page_visits(id),
  canonical_url TEXT NOT NULL,
  url TEXT NOT NULL,
  title TEXT,
  domain VARCHAR(255),
  scheduled_for TIMESTAMP NOT NULL,
  estimated_duration INTEGER, -- seconds
  calendar_event_id VARCHAR(255), -- if integrated with calendar
  status VARCHAR(50) DEFAULT 'scheduled', -- 'scheduled', 'completed', 'rescheduled', 'cancelled'
  completed_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_scheduled_reading_user_time ON scheduled_reading(user_id, scheduled_for)
  WHERE status = 'scheduled';
```

**API Endpoints:**
```
GET  /api/v1/patterns/serial-openers        # Get detected serial openers
POST /api/v1/resources/pin                  # Pin a resource
POST /api/v1/resources/schedule-reading     # Schedule reading time
GET  /api/v1/resources/pinned               # Get pinned resources
```

---

#### 4. Smart Scheduling
**Help user schedule time to actually read:**

**Algorithm:**
```sql
-- Find user's best reading times from historical data
WITH reading_patterns AS (
  SELECT
    EXTRACT(DOW FROM visited_at) as day_of_week,
    EXTRACT(HOUR FROM visited_at) as hour_of_day,
    AVG(engagement_rate) as avg_engagement,
    COUNT(*) as reading_sessions
  FROM page_visits
  WHERE user_id = :user_id
    AND engagement_rate > 0.5  -- Actually reading
    AND visited_at > NOW() - INTERVAL '90 days'
  GROUP BY day_of_week, hour_of_day
  HAVING COUNT(*) >= 3  -- Need enough data
)
SELECT
  day_of_week,
  hour_of_day,
  avg_engagement,
  reading_sessions
FROM reading_patterns
ORDER BY avg_engagement DESC, reading_sessions DESC
LIMIT 5;
```

**UX:**
- "You usually read best on Tuesday afternoons around 2pm. Schedule this for then?"
- Show calendar-like view with suggested slots
- One-click schedule

---

## Feature 3: Research Rabbit Holes 🐇

### Goal
Detect when users go deep on a topic (opening many related tabs) and group them into a recoverable "research session".

### Detection Logic
```sql
-- Find tab bursts from same domain
WITH tab_bursts AS (
  SELECT
    user_id,
    domain,
    visited_at,
    LAG(visited_at) OVER (PARTITION BY user_id, domain ORDER BY visited_at) as prev_visit
  FROM page_visits
  WHERE user_id = :user_id
    AND visited_at > NOW() - INTERVAL '7 days'
)
SELECT
  domain,
  COUNT(*) as tab_count,
  MIN(visited_at) as session_start,
  MAX(visited_at) as session_end,
  EXTRACT(EPOCH FROM (MAX(visited_at) - MIN(visited_at))) / 60 as duration_minutes
FROM tab_bursts
WHERE (visited_at - prev_visit) < INTERVAL '10 minutes'
  OR prev_visit IS NULL
GROUP BY domain, DATE_TRUNC('hour', visited_at)
HAVING COUNT(*) >= 5
ORDER BY session_start DESC;
```

### What We Need to Prepare

#### 1. Research Session Grouping
**Problem:** Identify which tabs belong to the same "research session".

**Approach:**
- Group tabs opened within 10min of each other
- From same or related domains
- Or with similar topics (keyword extraction)

**Algorithm:**
```javascript
// Pseudo-code for session detection
function detectResearchSessions(pageVisits) {
  const sessions = [];
  let currentSession = null;
  const TIME_WINDOW = 10 * 60 * 1000; // 10 minutes

  pageVisits.sort((a, b) => a.visited_at - b.visited_at);

  for (const visit of pageVisits) {
    if (!currentSession) {
      currentSession = { tabs: [visit], start: visit.visited_at };
      continue;
    }

    const timeSinceLast = visit.visited_at - currentSession.tabs[currentSession.tabs.length - 1].visited_at;

    if (timeSinceLast <= TIME_WINDOW) {
      // Same session - add tab
      currentSession.tabs.push(visit);
    } else {
      // New session - save current and start new
      if (currentSession.tabs.length >= 5) {
        sessions.push(currentSession);
      }
      currentSession = { tabs: [visit], start: visit.visited_at };
    }
  }

  // Don't forget last session
  if (currentSession && currentSession.tabs.length >= 5) {
    sessions.push(currentSession);
  }

  return sessions;
}
```

---

#### 2. Research Sessions Table
```sql
CREATE TABLE research_sessions (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  session_name VARCHAR(255), -- Auto-generated or user-named
  session_start TIMESTAMP NOT NULL,
  session_end TIMESTAMP NOT NULL,
  tab_count INTEGER NOT NULL,
  primary_domain VARCHAR(255),
  domains TEXT[], -- All domains in session
  topics TEXT[], -- Extracted keywords/topics
  total_duration_seconds INTEGER,
  avg_engagement_rate FLOAT,
  status VARCHAR(50) DEFAULT 'detected', -- 'detected', 'saved', 'restored', 'dismissed'
  saved_at TIMESTAMP,
  last_restored_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_research_sessions_user ON research_sessions(user_id);
CREATE INDEX idx_research_sessions_status ON research_sessions(status);

-- Link page visits to sessions
CREATE TABLE research_session_tabs (
  id BIGSERIAL PRIMARY KEY,
  session_id BIGINT REFERENCES research_sessions(id) ON DELETE CASCADE,
  page_visit_id VARCHAR(255) REFERENCES page_visits(id),
  tab_order INTEGER, -- Order opened in session
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_session_tabs_session ON research_session_tabs(session_id);
```

---

#### 3. Auto-Naming Sessions
**Generate meaningful names for research sessions:**

**Approach 1 - Domain-based:**
```javascript
function generateSessionName(session) {
  const domainCounts = {};
  session.tabs.forEach(tab => {
    domainCounts[tab.domain] = (domainCounts[tab.domain] || 0) + 1;
  });

  const topDomain = Object.keys(domainCounts).sort((a, b) =>
    domainCounts[b] - domainCounts[a]
  )[0];

  const date = new Date(session.start).toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit'
  });

  return `${topDomain} Research - ${date}`;
  // Example: "stackoverflow.com Research - Oct 16, 2:30 PM"
}
```

**Approach 2 - Topic-based (Advanced):**
```javascript
// Extract common keywords from titles
function extractTopics(tabs) {
  const stopWords = ['the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for'];
  const wordCounts = {};

  tabs.forEach(tab => {
    const words = tab.title.toLowerCase()
      .split(/\W+/)
      .filter(w => w.length > 3 && !stopWords.includes(w));

    words.forEach(word => {
      wordCounts[word] = (wordCounts[word] || 0) + 1;
    });
  });

  // Get top 3 words
  return Object.keys(wordCounts)
    .sort((a, b) => wordCounts[b] - wordCounts[a])
    .slice(0, 3);
}

// Usage:
// topics = ["react", "hooks", "testing"]
// name = "React, Hooks, Testing Session - Oct 16"
```

---

#### 4. Session Detection Job
**Background job to detect research sessions:**

```ruby
# app/jobs/detect_research_sessions_job.rb
class DetectResearchSessionsJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find(user_id)

    # Get recent page visits
    visits = user.page_visits
      .where('visited_at > ?', 7.days.ago)
      .order(visited_at: :asc)
      .to_a

    sessions = ResearchSessionDetector.detect(visits)

    sessions.each do |session|
      next if session[:tabs].length < 5

      research_session = ResearchSession.create!(
        user: user,
        session_name: generate_session_name(session),
        session_start: session[:start],
        session_end: session[:end],
        tab_count: session[:tabs].length,
        primary_domain: session[:primary_domain],
        domains: session[:domains],
        topics: session[:topics],
        total_duration_seconds: session[:total_duration],
        avg_engagement_rate: session[:avg_engagement]
      )

      # Link tabs to session
      session[:tabs].each_with_index do |tab, index|
        ResearchSessionTab.create!(
          session: research_session,
          page_visit_id: tab.id,
          tab_order: index
        )
      end
    end
  end
end
```

**Schedule:**
```ruby
# config/schedule.rb (using whenever gem)
every 1.hour do
  runner "User.find_each { |user| DetectResearchSessionsJob.perform_later(user.id) }"
end
```

---

#### 5. Session Restoration
**Allow users to restore entire research sessions:**

**API Endpoint:**
```
POST /api/v1/research-sessions/:id/restore

Response:
{
  "success": true,
  "session": {
    "id": 123,
    "name": "React Testing Research - Oct 16, 2:30 PM",
    "tab_count": 8,
    "tabs": [
      {
        "url": "https://stackoverflow.com/...",
        "title": "How to test React hooks",
        "order": 1
      },
      // ... more tabs
    ]
  }
}
```

**Browser Extension:**
```javascript
// Restore all tabs in order
async function restoreResearchSession(sessionId) {
  const response = await fetch(`/api/v1/research-sessions/${sessionId}/restore`, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}` }
  });

  const { session } = await response.json();

  // Open all tabs in order
  for (const tab of session.tabs) {
    await chrome.tabs.create({
      url: tab.url,
      active: false // Don't steal focus
    });
  }

  // Show notification
  chrome.notifications.create({
    type: 'basic',
    title: 'Research Session Restored',
    message: `Opened ${session.tab_count} tabs from "${session.name}"`
  });
}
```

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)
- [ ] Add session tracking to page_visits table
- [ ] Implement session heartbeat in browser extension
- [ ] Create tab_sessions table and tracking
- [ ] Add canonical_url normalization
- [ ] Create reading_list_items table
- [ ] Build basic reading list API endpoints

### Phase 2: Detection (Week 3-4)
- [ ] Build hoarder tab detection query
- [ ] Build serial opener detection query
- [ ] Implement research session detection algorithm
- [ ] Create research_sessions table
- [ ] Create background job for session detection
- [ ] Test detection accuracy with real data

### Phase 3: User Actions (Week 5-6)
- [ ] Build "save to reading list" functionality
- [ ] Implement pinned resources
- [ ] Create scheduled reading feature
- [ ] Build session restoration in browser extension
- [ ] Create notification system

### Phase 4: UI/UX (Week 7-8)
- [ ] Design and build dashboard
- [ ] Create browser extension popup UI
- [ ] Implement in-app notifications
- [ ] Build settings/preferences page
- [ ] User testing and feedback

---

## Technical Dependencies

### Browser Extension Capabilities Needed
1. **Tab Lifecycle Tracking**
   - Detect when tabs are created
   - Detect when tabs are closed (user close vs. session end)
   - Track tabs across browser restarts
   - Send heartbeat for open tabs

2. **Session Management**
   - Generate unique session IDs
   - Detect browser restart vs. crash
   - Persist session data locally
   - Sync with backend

3. **Tab Restoration**
   - Open multiple tabs programmatically
   - Restore tab order
   - Handle pinned tabs differently

### API Requirements
1. **Real-time Updates**
   - WebSocket or polling for live tab status
   - Push notifications for alerts

2. **Bulk Operations**
   - Bulk add to reading list
   - Bulk session restoration
   - Batch updates for performance

3. **Query Performance**
   - Indexes on frequently queried fields
   - Caching for detection queries
   - Pagination for large result sets

### Database Considerations
1. **Indexes Needed**
   ```sql
   CREATE INDEX idx_page_visits_user_open ON page_visits(user_id, is_currently_open);
   CREATE INDEX idx_page_visits_session ON page_visits(session_id);
   CREATE INDEX idx_page_visits_canonical ON page_visits(canonical_url);
   CREATE INDEX idx_page_visits_visited_at ON page_visits(visited_at DESC);
   ```

2. **Data Retention**
   - Keep page_visits for 90 days
   - Archive old research sessions
   - Clean up dismissed items after 30 days

---

## Success Metrics

### Detection Accuracy
- % of correctly identified hoarder tabs (user feedback)
- % of serial openers that users actually pin/schedule
- % of research sessions that users save/restore

### User Engagement
- Reading list completion rate
- Average time to complete reading list item
- Session restoration frequency
- User retention (weekly active users)

### System Performance
- Detection query performance (< 100ms)
- Session detection job completion time
- API response times
- Browser extension memory/CPU usage

---

## Open Questions

1. **Session Tracking:**
   - How do we handle tabs that are suspended/hibernated by browser?
   - Should we track tabs in background vs. foreground?

2. **Privacy:**
   - How much data should we store?
   - What about sensitive URLs (banking, etc.)?
   - Should users be able to exclude certain domains?

3. **User Experience:**
   - How aggressive should notifications be?
   - Should we auto-close hoarder tabs or just suggest?
   - What's the right threshold for "serial opener" (3 times? 5 times?)?

4. **Scalability:**
   - How many open tabs do power users have?
   - What's the max number of sessions to track?
   - Should we limit reading list size?

---

**Document Version:** 1.0
**Last Updated:** 2025-10-16
**Status:** Implementation Planning
