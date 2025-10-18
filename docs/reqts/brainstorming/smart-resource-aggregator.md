# Smart Resource Aggregator - Feature Brainstorming

**Problem Statement:** ADHD users often open tabs/resources with intent to read later, get distracted, and accidentally close them without reading. We need a smart system to recover these resources and resurface them at the right time.

**Target User:** People with ADHD who struggle with:
- Tab hoarding (keeping many tabs open "to read later")
- Accidental closures
- Context switching and losing track of what they were doing
- Getting distracted mid-task

---

## Data Available

Our `page_visits` table provides rich signals:

| Field | What It Tells Us |
|-------|------------------|
| `duration_seconds` | How long the tab was open |
| `active_duration_seconds` | Time actually engaged/reading |
| `engagement_rate` | % of time actively reading (0-1) |
| `idle_periods` | When user got distracted |
| `visited_at` | Timestamp of opening |
| `url`, `domain`, `title` | Content identification |
| `tab_id` | Tab tracking |

---

## Feature Categories

## 1. Accidental Closures - Quick Recovery

### 1.1 Zombie Tabs 🧟
**Detection Logic:**
```
duration_seconds > 120 AND active_duration_seconds < 10
```
**Signal:** "You opened this but never read it"

**Example Use Case:** Opened a Reddit post, got a notification, closed the tab accidentally

**UX:**
- Badge notification: "12 zombie tabs found"
- Click to see list sorted by recency
- Actions: Save to reading list, restore tab, dismiss

---

### 1.2 Tab Cemetery ⚰️
**Detection Logic:**
```
(closed_at - visited_at) < 30 seconds
```
**Signal:** "Oops, wrong close?"

**Recovery Window:** Last 24 hours

**UX:**
- Quick recovery panel: "Recently closed" with thumbnails
- One-click restore
- Bulk restore by time range

---

### 1.3 The Unfinished 📖
**Detection Logic:**
```
engagement_rate > 0.5 AND duration_seconds < 60
```
**Signal:** "You were reading this, then got interrupted"

**Example:** Article you were halfway through when phone rang

**UX:**
- "Resume reading" section
- Shows with context: "You were reading this at 2:45pm"
- Estimate: "~3min remaining"

---

## 2. Read It Later - Smart Queue

### 2.1 The Hoarder's Stack 📚
**Detection Logic:**
```
duration_seconds > 300
AND engagement_rate < 0.05
AND tab_still_open = true
```
**Signal:** "You're keeping this tab open 'to read later'"

**Action:**
- Auto-save to reading list
- Suggest closing to reduce cognitive load
- Group similar hoarder tabs

**UX:**
- Weekly notification: "You have 15 tabs open but unread"
- Bulk action: "Save all to 'Weekend Reading' and close"

---

### 2.2 Serial Openers 🔄
**Detection Logic:**
```sql
SELECT domain, COUNT(*) as opens
FROM page_visits
WHERE duration_seconds < 120
GROUP BY domain
HAVING COUNT(*) >= 3
```
**Signal:** "You keep coming back to this but never finish"

**Smart Action:**
- Pin the resource
- Schedule dedicated reading time
- "You've opened Medium articles 5 times this week but only finished 1"

---

### 2.3 Research Rabbit Holes 🐇
**Detection Logic:**
```sql
SELECT domain, COUNT(*) as tab_count
FROM page_visits
WHERE visited_at BETWEEN (NOW() - INTERVAL '10 minutes') AND NOW()
GROUP BY domain
HAVING COUNT(*) >= 5
```
**Signal:** "You went deep on this topic"

**Action:**
- Group as "Research Session" with timestamp
- Save entire session for later restoration
- Tag by topic (auto-detect from URLs/titles)

**Example:** Stack Overflow + GitHub + Docs = "Debugging session on React hooks"

---

## 3. Context Recovery - ADHD-Specific

### 3.1 Task Clusters 🧩
**Detection Logic:**
```
Tabs opened in burst (< 5min between) + related domains
```

**Algorithm:**
1. Find tabs opened within 5min window
2. Cluster by domain similarity
3. Detect common patterns:
   - stackoverflow.com + github.com + docs = "Coding session"
   - multiple article domains = "Research session"
   - shopping sites = "Product comparison"

**UX:**
- "Resume your debugging session from 2pm?" (shows 8 tabs)
- One-click restore entire cluster
- Show session duration and engagement

---

### 3.2 The Distraction Trail 🦋
**Detection Logic:**
```
Tab A (high engagement) → Tab B (low engagement) → Tab C (low engagement)
```

**Algorithm:**
1. Track tab opening sequence
2. Find tabs with engagement_rate > 0.7
3. Identify subsequent tabs with < 0.2 engagement
4. These are "distraction tabs"

**Signal:** "You got distracted mid-task"

**Recovery:**
- Highlight Tab A: "Go back to what you were actually doing"
- Hide/suggest closing distraction tabs

---

### 3.3 Focus Time Finder ⏰
**Detection Logic:**
```sql
SELECT
  DATE_TRUNC('hour', visited_at) as hour_window,
  AVG(engagement_rate) as avg_engagement,
  COUNT(*) as tabs_used
FROM page_visits
GROUP BY hour_window
HAVING AVG(engagement_rate) > 0.6
```

**Signal:** "You were in the zone between 2-4pm"

**Action:**
- "Want to resume these tabs during your next focus session?"
- Learn user's productive hours
- Suggest opening saved tabs during similar time windows

---

## 4. Smart Resurfacing - Proactive

### 4.1 Weekly Graveyard Digest 📅
**Trigger:** Every Sunday morning

**Content:** "Here are 10 tabs you closed but never read"

**Sorting Algorithm:**
```
intent_score = duration_seconds * (1 - engagement_rate)
```
Higher score = more likely you wanted to read but didn't

**UX:**
- Email digest with thumbnails
- One-click actions: Save, Open, Dismiss
- Summary: "You saved 3, dismissed 2, opened 1"

---

### 4.2 Deja Vu Detector 🔮
**Detection Logic:**
```
Current URL/domain matches zombie tab from past 7 days
```

**Alert:** "You opened a similar article last week but never read it. Here's that one too."

**Example:**
- Today: Open "How to use React Hooks"
- Alert: "You also opened 'React Hooks Best Practices' 3 days ago (unread)"

---

### 4.3 Context-Aware Surfacing 🎨
**Trigger:** User opens specific domain

**Algorithm:**
1. Detect domain of newly opened tab
2. Query zombie tabs from same domain or related context
3. Surface if relevant (< 7 days old)

**Example:**
- User opens GitHub
- Suggest: "You have 3 unread GitHub discussions from last week"

**Smart Timing:** Only show when relevant (don't interrupt)

---

## 5. Save for Later - Action-Oriented

### 5.1 One-Click Collections 📂
**Features:**
- Quick-save zombie tabs to named collections
- Auto-suggest collection names: "Startup Ideas", "ADHD Resources", "Need to Reply"
- Auto-tag by domain/topic using ML or simple keyword extraction

**UX:**
- Right-click menu: "Add to collection"
- Keyboard shortcut: Cmd+Shift+S
- Bulk collection creation from dashboard

---

### 5.2 Reading Time Estimator ⏱️
**Algorithm:**
```
estimated_reading_time = word_count / 200 (words per minute)
```

**Features:**
- Calculate: "This article would take ~8min to read"
- Schedule: "Block 10min on calendar to read this?"
- Track completion: Mark as read when engagement_rate > 0.7

**UX:**
- Show estimate on save
- Filter by reading time: "Show me 5min articles"
- Progress bar during reading

---

### 5.3 Smart Reminders 🔔
**Trigger Logic:**
- Saved X days ago (3, 7, 14 days)
- During user's typical low-activity periods
- Or during learned "reading hours"

**Example:**
- "You saved this Medium article 3 days ago"
- "You usually read between 8-9pm, want to read these then?"

**UX:**
- Gentle notifications (not pushy)
- Snooze options
- "Not interested" removes from queue

---

## 6. ADHD Superpowers - Leverage Patterns

### 6.1 Hyperfocus Recovery 🚀
**Detection Logic:**
```
20+ tabs opened in < 30min
AND all related domains
AND avg(engagement_rate) > 0.5
```

**Signal:** "You went deep on [topic]. Save this research session?"

**Action:**
- One-click save entire hyperfocus session
- Auto-name: "React Testing Research - Oct 16, 2-4pm"
- Restore entire session later with one click

---

### 6.2 The "Oh Shit" Button 🆘
**Purpose:** Panic recovery for accidental closures

**Features:**
- Shows last 50 closed tabs with thumbnails
- Visual timeline view
- One-click bulk restore by time window
- Filter by domain
- Search by title/URL

**UX:**
- Prominent button in toolbar
- Keyboard shortcut: Cmd+Shift+T (multiple times)
- "Restore last 5min of browsing"

---

### 6.3 Pattern Learning 🧠
**Machine Learning Features:**
- Track which domains user finishes reading vs abandons
- Learn optimal reading times
- Predict which saved tabs will actually be read

**Insights:**
- "You tend to abandon tabs from [domain] after 30 seconds"
- "But you always finish articles from [other domain]"
- "You're most productive 2-4pm on weekdays"

**Actions:**
- Auto-categorize new tabs based on learned patterns
- Don't save tabs from domains user never reads
- Surface high-value tabs during productive hours

---

## Killer Feature: The ADHD Recovery Dashboard

### Visual Layout
```
┌─────────────────────────────────────────────────┐
│  🆘 Recently Closed (Last 1hr)             [5]  │
│  ────────────────────────────────────────────   │
│  🧟 Zombie Tabs (Opened but unread)      [12]   │
│  ────────────────────────────────────────────   │
│  📖 Half-Read Articles                    [3]   │
│  ────────────────────────────────────────────   │
│  🐇 Research Sessions                     [2]   │
│  ────────────────────────────────────────────   │
│  ⏰ Saved for Focus Time                  [8]   │
│  ────────────────────────────────────────────   │
│  🔄 Serial Openers                        [4]   │
└─────────────────────────────────────────────────┘
```

### Smart Actions
- **Bulk Actions:** "Save all zombies to 'Weekend Reading'"
- **Time-Based:** "Show me tabs from my last productive session"
- **Context Switching:** "I'm done with work, hide all work tabs but save them"
- **One-Click Recovery:** Restore entire categories

### Dashboard Features
1. **Quick Stats**
   - Tabs saved this week
   - Reading completion rate
   - Most productive hours
   - Top domains

2. **Action Center**
   - Process all zombies
   - Review weekly digest
   - Restore recent session
   - Clean up collections

3. **Insights**
   - "You saved 23 tabs but only read 5 this week"
   - "Your reading completion rate increased 40%"
   - "You're most focused on Tuesday afternoons"

---

## Priority Ranking

### MVP Features (Phase 1)
1. **Zombie Tabs** - Catches accidental closures
2. **Tab Cemetery** - Quick recovery for recent closures
3. **The "Oh Shit" Button** - Panic recovery
4. **One-Click Collections** - Basic save for later

### High Impact (Phase 2)
5. **Task Clusters** - Helps resume interrupted work
6. **Weekly Graveyard Digest** - Reviews what you missed
7. **The Unfinished** - Resume reading interrupted content
8. **Reading Time Estimator** - Helps with time management

### Nice to Have (Phase 3)
9. **Pattern Learning** - Gets smarter over time
10. **Hyperfocus Recovery** - Save deep research sessions
11. **Context-Aware Surfacing** - Smart timing
12. **Smart Reminders** - Gentle nudges to read saved content

---

## Technical Implementation Notes

### API Endpoints Needed
```
GET  /api/v1/resources/zombie-tabs
GET  /api/v1/resources/recently-closed
GET  /api/v1/resources/unfinished
GET  /api/v1/resources/task-clusters
POST /api/v1/resources/collections
GET  /api/v1/resources/collections/:id
POST /api/v1/resources/restore
GET  /api/v1/resources/insights
```

### Database Schema Additions
```sql
-- Collections table
CREATE TABLE resource_collections (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  name VARCHAR(255),
  description TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

-- Collection items (many-to-many)
CREATE TABLE collection_items (
  id BIGSERIAL PRIMARY KEY,
  collection_id BIGINT REFERENCES resource_collections(id),
  page_visit_id VARCHAR(255) REFERENCES page_visits(id),
  added_at TIMESTAMP,
  status VARCHAR(50) -- 'unread', 'reading', 'completed', 'dismissed'
);

-- User insights/patterns
CREATE TABLE user_browsing_patterns (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  pattern_type VARCHAR(100), -- 'focus_hours', 'abandoned_domains', etc.
  pattern_data JSONB,
  confidence_score FLOAT,
  last_updated TIMESTAMP
);
```

### Processing Jobs
- **Daily Digest Job** - Process zombie tabs
- **Weekly Digest Job** - Send email summary
- **Pattern Learning Job** - Update ML models
- **Cleanup Job** - Remove old dismissed items

---

## Success Metrics

### User Engagement
- % of zombie tabs recovered vs dismissed
- Reading completion rate (engagement_rate > 0.7)
- Collections created per user
- Dashboard visits per week

### ADHD-Specific Metrics
- Time to recover from distraction (task cluster restoration)
- Number of "Oh Shit" button uses
- Session restoration success rate
- User retention (are users coming back?)

### Business Metrics
- User activation rate
- Feature adoption rate
- User feedback scores
- Reduced tab bloat (tabs per user over time)

---

## Next Steps

1. **Validate with Users**
   - Survey ADHD users on which features resonate
   - Prototype dashboard mockups
   - A/B test detection algorithms

2. **Technical Spike**
   - Implement zombie tab detection
   - Build basic dashboard
   - Test performance with large datasets

3. **Iterate**
   - Start with MVP features
   - Gather feedback
   - Add Phase 2 features based on usage data

---

**Document Version:** 1.0
**Last Updated:** 2025-10-16
**Status:** Brainstorming / Concept Phase
