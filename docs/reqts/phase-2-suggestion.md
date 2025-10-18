# Phase 2 Suggestion: Browsing Insights & Analytics

## Overview

**Phase 1** covered the foundation:
- Docker setup
- Project setup
- User authentication & management
- Email verification & password reset
- Data ingestion API (page_visits, tab_aggregates)
- Background jobs

**Phase 3** covers intelligent pattern detection:
- Hoarder tabs, serial openers, research sessions
- Reading list
- Research session restoration
- Smart resource aggregation

**Phase 2 should bridge these two** by providing insights and analytics on the browsing data that's already being collected.

---

## Proposed Phase 2: Browsing Insights & Analytics

### Goals
1. Help users understand their browsing habits
2. Provide actionable insights (productive hours, top sites, time spent)
3. Create foundation for Phase 3 pattern detection
4. Build dashboard for visualizing browsing data

---

## Phase 2 Feature Set

### 1. Daily/Weekly Summary API
**What:** Aggregate browsing statistics for a time period

**Endpoints:**
- `GET /api/v1/insights/daily_summary?date=2025-10-16`
- `GET /api/v1/insights/weekly_summary?week=2025-W42`

**Data Returned:**
```json
{
  "total_sites_visited": 45,
  "total_time_seconds": 14400,
  "active_time_seconds": 8200,
  "avg_engagement_rate": 0.57,
  "most_productive_hour": "14:00-15:00",
  "top_domains": [
    { "domain": "github.com", "visit_count": 23, "time_spent": 3600 }
  ]
}
```

---

### 2. Top Sites & Time Spent
**What:** Show which sites user spends most time on

**Endpoints:**
- `GET /api/v1/insights/top_sites?period=week&limit=10`
- `GET /api/v1/insights/time_by_domain?period=month`

**Use Cases:**
- "You spent 12 hours on GitHub this week"
- "Your top 5 sites are..."
- "You visited Stack Overflow 45 times but only stayed 2 min each"

---

### 3. Productivity Patterns
**What:** Identify when user is most productive/focused

**Endpoints:**
- `GET /api/v1/insights/productivity_hours`
- `GET /api/v1/insights/focus_sessions`

**Data:**
- Hours of day with highest engagement rates
- Days of week with most focus
- Longest focused sessions (high engagement, minimal tab switching)

**Use Cases:**
- "You're most productive 2-4pm on Tuesdays"
- "Your best focus session was Oct 15, 2-3:30pm"

---

### 4. Browsing Timeline
**What:** Visual timeline of browsing activity

**Endpoint:**
- `GET /api/v1/insights/timeline?start_date=2025-10-15&end_date=2025-10-16`

**Data:**
- Hour-by-hour breakdown
- Sites visited per hour
- Active vs. idle time
- Context switches (tab changes)

---

### 5. Domain Categories & Tagging
**What:** Auto-categorize domains (work, social, learning, etc.)

**Features:**
- Pre-defined categories (work tools, social media, news, learning)
- Auto-tag common domains (github.com = work, twitter.com = social)
- User-customizable categories
- Time spent per category

**Endpoints:**
- `GET /api/v1/insights/time_by_category`
- `POST /api/v1/domain_categories` (customize categories)

---

### 6. Engagement Metrics
**What:** Detailed engagement analysis

**Endpoints:**
- `GET /api/v1/insights/engagement_trends?period=month`
- `GET /api/v1/insights/low_engagement_sites`

**Metrics:**
- Average engagement rate over time
- Sites with consistently low engagement
- Sites with consistently high engagement
- Engagement by time of day

---

### 7. Recent Activity Feed
**What:** Show recent browsing activity with context

**Endpoint:**
- `GET /api/v1/insights/recent_activity?limit=50`

**Data:**
```json
{
  "activities": [
    {
      "timestamp": "2025-10-16T14:30:00Z",
      "type": "browsing_session",
      "sites": ["github.com", "stackoverflow.com"],
      "duration_minutes": 45,
      "engagement_rate": 0.82,
      "context": "Coding session - high focus"
    }
  ]
}
```

---

### 8. Insights Dashboard (Frontend)
**What:** Visual dashboard for browsing insights

**Components:**
- **Today's Summary Card** - Sites visited, time spent, productivity score
- **Weekly Chart** - Time spent per day, engagement trends
- **Top Sites List** - Most visited, most time spent
- **Productivity Heatmap** - Hours/days of high focus
- **Category Breakdown** - Pie chart of time by category
- **Recent Activity Timeline** - Recent browsing sessions

---

## Technical Implementation

### Database Changes
**New Tables:**

1. **`browsing_summaries`** (cached daily/weekly stats)
```sql
CREATE TABLE browsing_summaries (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  period_type VARCHAR(20), -- 'day', 'week', 'month'
  period_start DATE,
  period_end DATE,
  total_sites_visited INTEGER,
  total_time_seconds INTEGER,
  active_time_seconds INTEGER,
  avg_engagement_rate FLOAT,
  top_domains JSONB,
  stats JSONB,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

2. **`domain_categories`** (domain categorization)
```sql
CREATE TABLE domain_categories (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  domain VARCHAR(255),
  category VARCHAR(100), -- 'work', 'social', 'learning', 'news', etc.
  is_system BOOLEAN DEFAULT false, -- pre-defined vs. user-created
  created_at TIMESTAMP
);
```

---

### Background Jobs

1. **`GenerateDailySummaryJob`** - Runs daily at midnight
   - Aggregates yesterday's browsing data
   - Caches in `browsing_summaries` table
   - Improves query performance

2. **`GenerateWeeklySummaryJob`** - Runs weekly on Monday
   - Aggregates last week's data
   - Calculates trends

3. **`CategorizeDomainJob`** - Runs on new domains
   - Auto-categorize based on domain name
   - Use simple keyword matching initially
   - Can add ML later

---

### Services

1. **`Insights::DailySummaryService`**
   - Aggregates page_visits and tab_aggregates
   - Calculates metrics
   - Caches results

2. **`Insights::ProductivityAnalyzer`**
   - Identifies productive hours
   - Finds focus sessions
   - Calculates productivity scores

3. **`Insights::DomainCategorizer`**
   - Auto-categorize domains
   - Match against known patterns
   - Allow user overrides

---

## API Endpoints Summary

### Insights
- `GET /api/v1/insights/daily_summary`
- `GET /api/v1/insights/weekly_summary`
- `GET /api/v1/insights/top_sites`
- `GET /api/v1/insights/time_by_domain`
- `GET /api/v1/insights/productivity_hours`
- `GET /api/v1/insights/focus_sessions`
- `GET /api/v1/insights/timeline`
- `GET /api/v1/insights/time_by_category`
- `GET /api/v1/insights/engagement_trends`
- `GET /api/v1/insights/recent_activity`

### Domain Management
- `GET /api/v1/domain_categories`
- `POST /api/v1/domain_categories`
- `PATCH /api/v1/domain_categories/:id`
- `DELETE /api/v1/domain_categories/:id`

**Total:** ~14 new endpoints

---

## Timeline Estimate

### Week 1: Core Insights APIs
- Daily/weekly summary service
- Top sites & time spent
- Timeline API
- Background jobs for caching

### Week 2: Productivity & Categories
- Productivity patterns analyzer
- Focus session detection
- Domain categorization
- Engagement metrics

### Week 3: Dashboard UI
- Summary cards
- Charts & visualizations
- Category management
- Recent activity feed

### Week 4: Polish & Testing
- Tests for all services
- Performance optimization
- User testing
- Documentation

**Total:** 3-4 weeks (similar to Phase 3)

---

## Why Phase 2 Makes Sense

### Builds on Phase 1
- Uses existing `page_visits` and `tab_aggregates` data
- No new data collection needed
- Adds value to data already being gathered

### Prepares for Phase 3
- Domain categorization helps with pattern detection
- Productivity analysis feeds into "hoarder tab" detection
- Engagement metrics used in "serial opener" identification
- Timeline view helps understand browsing context

### Standalone Value
- Users get immediate insights without waiting for Phase 3
- Dashboard is useful on its own
- Helps validate data quality before building patterns

### Progressive Complexity
- **Phase 1:** Foundation (auth, data collection)
- **Phase 2:** Insights (understand the data) ← THIS
- **Phase 3:** Intelligence (act on patterns)

---

## Sample User Flows

### Flow 1: Morning Dashboard Check
1. User opens dashboard
2. Sees yesterday's summary: "You visited 42 sites, spent 6.5 hours browsing"
3. Top site: GitHub (3.2 hours, high engagement)
4. Insight: "Your most productive time was 2-4pm"

### Flow 2: Weekly Review
1. User checks weekly summary
2. Sees time breakdown by category:
   - Work: 18 hours
   - Social: 8 hours
   - Learning: 5 hours
3. Insight: "You spent 40% more time on work sites this week"

### Flow 3: Productivity Analysis
1. User checks productivity hours
2. Sees heatmap: Most productive Mon-Wed, 2-5pm
3. Insight: "Schedule deep work during these times"
4. Action: User adjusts work schedule accordingly

---

## Success Metrics

### Engagement
- % of users who view insights weekly
- Average time spent on dashboard
- Most viewed insight types

### Data Quality
- Accuracy of domain categorization
- User satisfaction with insights
- Feedback on productivity patterns

### Foundation for Phase 3
- Number of domains categorized
- Quality of engagement data
- Focus session detection accuracy

---

## Future Enhancements (Phase 2.5 or Phase 4)

1. **Comparative Insights**
   - "You spent 20% more time on social media than last week"
   - Trends over time

2. **Goal Setting**
   - Set time limits per category
   - Track progress toward goals
   - Notifications when approaching limits

3. **AI Insights**
   - "You seem distracted on Friday afternoons"
   - "Your focus improves after lunch"
   - Personalized recommendations

4. **Export & Reporting**
   - Export insights to CSV
   - Generate weekly/monthly reports
   - Share insights (optional)

---

## Recommendation

**Phase 2 should focus on Browsing Insights & Analytics** because:

1. ✅ Natural progression from Phase 1 data collection
2. ✅ Provides immediate value to users
3. ✅ Prepares data/infrastructure for Phase 3 patterns
4. ✅ Similar scope/timeline to Phase 3 (3-4 weeks)
5. ✅ Can be built in parallel with Phase 3 if needed
6. ✅ Validates data quality before pattern detection

This creates a logical flow:
- **Phase 1:** Collect browsing data
- **Phase 2:** Understand browsing habits (insights)
- **Phase 3:** Act on patterns (smart resources)

---

**Status:** Proposed for Discussion
**Next Step:** Review and approve Phase 2 scope
**Estimated Timeline:** 3-4 weeks
**Dependencies:** Phase 1 complete
