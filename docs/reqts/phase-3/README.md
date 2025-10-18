# Phase 3: Smart Resource Aggregator - Implementation Guide

## Quick Start

This folder contains complete implementation documentation for Phase 3 features.

---

## Document Index

### 📋 Planning Documents

1. **[00-overview.md](./00-overview.md)**
   - High-level feature summary
   - Technical approach
   - Success metrics
   - 3-4 week timeline

### 🗄️ Technical Specifications

2. **[01-database-schema.md](./01-database-schema.md)**
   - 3 new tables: `reading_list_items`, `research_sessions`, `research_session_tabs`
   - Migrations with indexes
   - Data validation rules
   - Schema diagrams

3. **[02-api-endpoints.md](./02-api-endpoints.md)**
   - 17 REST API endpoints
   - Request/response examples
   - Error handling
   - Rate limiting

4. **[03-detection-logic.md](./03-detection-logic.md)**
   - SQL queries (tested & working)
   - Detection algorithms
   - Suggestion generators
   - Performance optimization

5. **[04-backend-implementation.md](./04-backend-implementation.md)**
   - Rails models with validations
   - Controllers with full CRUD
   - Service objects
   - Routes configuration

### 🌐 Frontend & Testing

6. **[05-browser-extension.md](./05-browser-extension.md)**
   - API client updates
   - Popup UI components
   - Session restoration
   - Reading list actions

7. **[06-testing-strategy.md](./06-testing-strategy.md)**
   - Model specs
   - Request specs
   - Service specs
   - Factory definitions
   - 95%+ coverage target

### 📅 Execution Plan

8. **[07-implementation-timeline.md](./07-implementation-timeline.md)**
   - Week-by-week breakdown
   - Daily task lists
   - Effort estimates (98-126 hours)
   - Success criteria

---

## Quick Reference

### What We're Building

**3 Core Features:**
1. **Hoarder Tabs** 📚 - Detect tabs open long with minimal engagement
2. **Serial Openers** 🔄 - Identify repeatedly opened but unfinished resources
3. **Research Sessions** 🐇 - Group related browsing bursts for restoration

**Supporting Features:**
- Reading list (save for later)
- Research session archiving
- Pattern detection APIs
- Browser extension integration

---

## Implementation Order

```
Week 1: Database + Detection APIs
├── Day 1-2: Migrations & Models
├── Day 3-4: Detection Services
└── Day 4-5: Pattern APIs

Week 2: CRUD APIs
├── Day 6-7: Reading List API
├── Day 8-9: Research Sessions API
└── Day 10: Bulk Operations

Week 3: Browser Extension
├── Day 11-12: API Client
├── Day 13: Popup UI
├── Day 14: Reading List Actions
└── Day 15: Session Restoration

Week 4: Polish & Launch
├── Day 16-17: Dashboard (optional)
├── Day 18: Testing & Fixes
├── Day 19: User Testing
└── Day 20: Documentation & Launch
```

---

## Getting Started

### Prerequisites

```bash
# Backend
- Rails 7.0+
- PostgreSQL 15+
- Ruby 3.2+

# Frontend
- React 18+
- Chrome Extension Manifest V3

# Tools
- Postman (for API testing)
- Git
- Docker (for local dev)
```

### Development Setup

```bash
# 1. Pull latest code
git checkout -b phase-3-smart-resources

# 2. Run migrations
cd apps/sync-be
rails db:migrate

# 3. Verify schema
rails dbconsole
\d reading_list_items
\d research_sessions

# 4. Test detection queries
rails console
user = User.first
Patterns::HoarderDetector.new(user, {}).call

# 5. Run tests
bundle exec rspec
```

---

## Key SQL Queries

### Hoarder Tabs
```sql
SELECT * FROM page_visits
WHERE user_id = 1
  AND duration_seconds > 300
  AND engagement_rate < 0.05
ORDER BY duration_seconds DESC;
```

### Serial Openers
```sql
SELECT domain, COUNT(*) as opens
FROM page_visits
WHERE user_id = 1
  AND duration_seconds < 120
  AND visited_at > NOW() - INTERVAL '30 days'
GROUP BY domain
HAVING COUNT(*) >= 3
ORDER BY COUNT(*) DESC;
```

### Research Sessions
```sql
SELECT domain, DATE_TRUNC('hour', visited_at) as hour, COUNT(*) as tabs
FROM page_visits
WHERE user_id = 1
  AND visited_at > NOW() - INTERVAL '7 days'
GROUP BY domain, hour
HAVING COUNT(*) >= 5
ORDER BY hour DESC;
```

---

## API Endpoints

### Pattern Detection
- `GET /api/v1/patterns/hoarder-tabs`
- `GET /api/v1/patterns/serial-openers`
- `GET /api/v1/patterns/research-sessions`

### Reading List
- `GET /api/v1/reading-list`
- `POST /api/v1/reading-list`
- `POST /api/v1/reading-list/bulk`
- `PATCH /api/v1/reading-list/:id`
- `DELETE /api/v1/reading-list/:id`

### Research Sessions
- `GET /api/v1/research-sessions`
- `GET /api/v1/research-sessions/:id`
- `POST /api/v1/research-sessions`
- `POST /api/v1/research-sessions/:id/save`
- `POST /api/v1/research-sessions/:id/restore`
- `PATCH /api/v1/research-sessions/:id`
- `DELETE /api/v1/research-sessions/:id`

---

## Testing

### Run All Tests
```bash
bundle exec rspec
```

### Run Specific Tests
```bash
bundle exec rspec spec/models/reading_list_item_spec.rb
bundle exec rspec spec/requests/api/v1/patterns_spec.rb
bundle exec rspec spec/services/patterns/
```

### Check Coverage
```bash
COVERAGE=true bundle exec rspec
open coverage/index.html
```

### Performance Tests
```bash
bundle exec rspec --tag performance
```

---

## Database Migrations

### Create Tables
```bash
rails generate migration CreateReadingListItems
rails generate migration CreateResearchSessions
rails generate migration CreateResearchSessionTabs
```

### Run Migrations
```bash
rails db:migrate
```

### Rollback (if needed)
```bash
rails db:rollback STEP=3
```

---

## Common Commands

### Generate Token for Testing
```bash
docker-compose exec sync-api bundle exec rails runner "
user = User.first
token = Authentication::TokenService.generate_jwt_token(user)
puts token
"
```

### Test API with cURL
```bash
TOKEN="your-jwt-token"

# Test hoarder tabs
curl -X GET "http://localhost:3001/api/v1/patterns/hoarder-tabs" \
  -H "Authorization: Bearer $TOKEN"

# Add to reading list
curl -X POST "http://localhost:3001/api/v1/reading-list" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"reading_list_item": {"url": "https://example.com", "title": "Test"}}'
```

### Rails Console Helpers
```ruby
# In Rails console

# Get user
user = User.first

# Detect patterns
hoarder = Patterns::HoarderDetector.new(user, {}).call
serial = Patterns::SerialOpenerDetector.new(user, {}).call
research = Patterns::ResearchSessionDetector.new(user, {}).call

# Create reading list item
item = user.reading_list_items.create!(
  url: 'https://example.com/article',
  title: 'Test Article',
  added_from: 'manual_save'
)

# Create research session
session = user.research_sessions.create!(
  session_name: 'Test Session',
  session_start: 1.hour.ago,
  session_end: Time.current,
  tab_count: 5,
  primary_domain: 'stackoverflow.com'
)
```

---

## Troubleshooting

### Issue: Detection queries too slow
**Solution:**
```sql
-- Add indexes
CREATE INDEX idx_page_visits_user_duration ON page_visits(user_id, duration_seconds);
CREATE INDEX idx_page_visits_user_engagement ON page_visits(user_id, engagement_rate);

-- Check query performance
EXPLAIN ANALYZE
SELECT * FROM page_visits WHERE user_id = 1 AND duration_seconds > 300;
```

### Issue: Tests failing
**Solution:**
```bash
# Reset test database
RAILS_ENV=test rails db:drop db:create db:migrate

# Re-run tests
bundle exec rspec
```

### Issue: API returns 401 Unauthorized
**Solution:**
```bash
# Generate fresh token
docker-compose exec sync-api bundle exec rails runner "
user = User.first
puts Authentication::TokenService.generate_jwt_token(user)
"
```

---

## Success Metrics

### Launch Criteria
- [ ] All 17 API endpoints working
- [ ] Test coverage > 90%
- [ ] Detection queries < 100ms
- [ ] Extension shows pattern counts
- [ ] Reading list functional
- [ ] Session restoration working

### Post-Launch Metrics
- API calls per day
- Reading list adoption rate
- Session restoration frequency
- User retention
- Query performance

---

## Next Steps

1. **Review all documents** in order (00-07)
2. **Set up development environment**
3. **Start with Week 1 tasks** (Database + APIs)
4. **Follow timeline** day by day
5. **Run tests frequently**
6. **Deploy to staging** for testing
7. **Launch to production**

---

## Support & Resources

### Documentation
- [Brainstorming Notes](../brainstorming/smart-resource-aggregator.md)
- [Simplified Plan](../brainstorming/what-we-actually-need.md)
- [Priority Features](../brainstorming/phase-priority-resource-patterns.md)

### Code Style
- [Rails Style Guide](https://github.com/rubocop/rails-style-guide)
- [Ruby Style Guide](https://github.com/rubocop/ruby-style-guide)
- [Better Specs](https://www.betterspecs.org)

### Tools
- [Postman Collection](../../postman/)
- [Database Schema](../../../db/schema.rb)
- [API Routes](../../../config/routes.rb)

---

## Questions?

- Check the specific document for details
- Review brainstorming notes for context
- Test queries in Rails console
- Run specs to verify functionality

---

**Status:** Ready for Implementation
**Last Updated:** 2025-10-16
**Estimated Effort:** 98-126 hours (3-4 weeks)
**Team:** Backend + Frontend developer(s)
