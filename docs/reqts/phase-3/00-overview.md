# Phase 3: Smart Resource Aggregator

## Overview

Phase 3 introduces intelligent resource pattern detection and management features to help users (especially those with ADHD) manage their browsing habits effectively.

## Core Features

### 1. The Hoarder's Stack 📚
Detect tabs that users keep open with intent to read but never actually engage with.

### 2. Serial Openers 🔄
Identify resources that users repeatedly open but never finish reading.

### 3. Research Rabbit Holes 🐇
Group related browsing sessions when users go deep on a topic.

---

## Project Structure

This phase is organized into multiple documents:

1. **00-overview.md** (this file) - High-level summary
2. **01-database-schema.md** - All database migrations and schema changes
3. **02-api-endpoints.md** - API endpoint specifications and contracts
4. **03-detection-logic.md** - SQL queries and detection algorithms
5. **04-backend-implementation.md** - Rails models, controllers, services
6. **05-browser-extension.md** - Extension changes needed
7. **06-frontend-dashboard.md** - Web UI implementation
8. **07-testing-strategy.md** - RSpec tests and test data
9. **08-implementation-timeline.md** - Week-by-week breakdown

---

## Technical Approach

### What We Already Have ✅
- `page_visits` table with duration, engagement_rate, visited_at
- `tab_aggregates` table with closed_at, total_time, active_time
- Browser extension tracking tab activity
- Detection queries already working with existing data

### What We Need to Build
1. **Reading List** - Save resources for later
2. **Research Sessions** - Save and restore browsing sessions
3. **Pattern Detection APIs** - Expose detection queries via REST API
4. **Browser Extension UI** - Display patterns and actions
5. **Web Dashboard** - Manage saved resources

---

## Key Principles

### 1. Leverage Existing Data
We don't need new tracking. All pattern detection works with current `page_visits` and `tab_aggregates` data.

### 2. Start Simple (MVP First)
- Phase 3.1: Detection APIs + Reading List
- Phase 3.2: Research Sessions
- Phase 3.3: Browser Extension UI
- Phase 3.4: Web Dashboard

### 3. User-Driven Actions
Detect patterns automatically, but let users decide what to save/dismiss.

### 4. Privacy First
- Users control what gets saved
- Sensitive domains can be excluded
- Data stays local to user account

---

## Success Metrics

### Detection Accuracy
- % of detected patterns that users take action on
- False positive rate (patterns users dismiss)

### User Engagement
- Reading list completion rate
- Session restoration frequency
- Weekly active users

### System Performance
- Detection query speed (< 100ms target)
- API response times (< 200ms target)
- Browser extension memory usage

---

## Development Timeline

**Total Estimate:** 3-4 weeks

- **Week 1:** Detection APIs + Reading List backend
- **Week 2:** Research Sessions backend
- **Week 3:** Browser Extension UI
- **Week 4:** Web Dashboard + Polish

See `08-implementation-timeline.md` for detailed breakdown.

---

## Dependencies

### Backend
- Rails 7.0+
- PostgreSQL 15+
- Existing authentication system
- Existing browsing data collection

### Browser Extension
- Chrome Extension Manifest V3
- Existing tab tracking functionality
- API client for backend communication

### Frontend (Dashboard)
- React 18+ (or existing frontend framework)
- Tailwind CSS (or existing styling)
- Chart library for insights (optional)

---

## Getting Started

1. Read through all phase-3 documents in order
2. Review database schema changes (`01-database-schema.md`)
3. Set up local development environment
4. Run existing detection queries to validate data
5. Begin with Week 1 tasks from timeline

---

## Questions & Clarifications

### Open Questions
- Should we auto-save hoarder tabs or require user action?
- What's the right threshold for "serial opener" (3x? 5x?)
- Should research sessions auto-expire after X days?
- Privacy: exclude certain domains by default (banking, etc.)?

### To Be Decided
- Notification strategy (in-app only? email digest?)
- Reading list size limits (if any)
- Data retention policy for patterns
- Mobile support timeline (future phase?)

---

## Related Documents

- **Brainstorming:** `../brainstorming/smart-resource-aggregator.md`
- **Simplified Plan:** `../brainstorming/what-we-actually-need.md`
- **Priority Features:** `../brainstorming/phase-priority-resource-patterns.md`

---

**Status:** Planning → Implementation Ready
**Last Updated:** 2025-10-16
**Owner:** HeyHo Platform Team
