# Phase 2: Sync Optimization & Basic Insights

## Quick Start

**Goal:** Optimize sync endpoint and add basic insights before Phase 3 pattern detection.

**Timeline:** 3-4 weeks
**Effort:** 80-100 hours
**Priority:** Before Phase 3

---

## What's in Phase 2?

### Week 1: Sync Optimization
- ✅ Incremental sync (only send changes)
- ✅ Conflict resolution (smart merge)
- ✅ Batch size limits
- ✅ Sync logging & history
- ✅ Sync status endpoint

**Expected Improvement:** 20x faster syncs, 200x smaller payloads

---

### Week 2: Data Quality
- ✅ Model validations (engagement, durations, timestamps)
- ✅ Data sanitization (clamp invalid values)
- ✅ Background cleanup job
- ✅ Health check endpoints
- ✅ Data quality monitoring

**Expected Improvement:** 99%+ data quality, no corrupt records

---

### Week 3: Insights APIs
- ✅ Daily/weekly summaries
- ✅ Top sites by domain
- ✅ Recent activity timeline
- ✅ Productivity hours analysis
- ✅ Server-side aggregation

**Expected Improvement:** Instant insights, no client-side processing

---

### Week 4: Polish & Testing
- ✅ Integration tests (95%+ coverage)
- ✅ API documentation
- ✅ Performance benchmarks
- ✅ Deployment prep

---

## Documents

### Read in Order

1. **[00-phase-2-overview.md](./00-phase-2-overview.md)** ← Start here
   - High-level overview
   - Current issues
   - Phase 2 scope
   - Success metrics

2. **[01-sync-optimization.md](./01-sync-optimization.md)**
   - Incremental sync implementation
   - Conflict resolution logic
   - SyncLog model
   - Extension changes

3. **[02-data-quality-validation.md](./02-data-quality-validation.md)**
   - Model validations
   - DataSanitizerService
   - CleanupCorruptDataJob
   - Health checks

4. **[03-insights-apis.md](./03-insights-apis.md)**
   - 5 new API endpoints
   - Service implementations
   - Caching strategy
   - Performance optimizations

5. **[04-implementation-timeline.md](./04-implementation-timeline.md)**
   - Week-by-week schedule
   - Day-by-day tasks
   - Checklists
   - Risk mitigation

---

## Quick Reference

### New Models

```ruby
# SyncLog - Track all sync operations
SyncLog.last_sync_for(user)
SyncLog.recent.limit(10)
```

### New Services

```ruby
# Sync optimization
DataSyncService.sync(user: user, page_visits: [], since: '2025-10-18T10:00:00Z')

# Data quality
DataSanitizerService.sanitize_page_visit(page_visit)
DataQualityService.generate_report

# Insights
Insights::DailySummaryService.call(user: user, date: Date.today)
Insights::TopSitesService.call(user: user, period: 'week', limit: 10)
Insights::RecentActivityService.call(user: user, limit: 20)
Insights::ProductivityHoursService.call(user: user, period: 'week')
```

### New API Endpoints

```bash
# Sync
POST   /api/v1/data/sync              # Optimized sync (with incremental support)
GET    /api/v1/data/sync/status       # Sync history & status

# Health
GET    /api/v1/health                 # System health
GET    /api/v1/health/data_quality    # Data quality report

# Insights
GET    /api/v1/insights/daily_summary
GET    /api/v1/insights/weekly_summary
GET    /api/v1/insights/top_sites
GET    /api/v1/insights/recent_activity
GET    /api/v1/insights/productivity_hours
```

---

## Implementation Checklist

### Before You Start

- [ ] Read all 5 documents
- [ ] Review current sync implementation
- [ ] Set up development environment
- [ ] Create feature branch: `git checkout -b phase-2-sync-optimization`

### Week 1
- [ ] Create `SyncLog` model
- [ ] Add incremental sync
- [ ] Implement conflict resolution
- [ ] Add batch limits
- [ ] Create sync status endpoint
- [ ] Update browser extension

### Week 2
- [ ] Add model validations
- [ ] Create `DataSanitizerService`
- [ ] Create `CleanupCorruptDataJob`
- [ ] Add health endpoints
- [ ] Run cleanup on existing data

### Week 3
- [ ] Create 5 insights services
- [ ] Add insights controller
- [ ] Add caching
- [ ] Add database indexes
- [ ] Test with real data

### Week 4
- [ ] Write integration tests
- [ ] Ensure 95%+ coverage
- [ ] Write API docs
- [ ] Performance testing
- [ ] Deploy to staging
- [ ] QA & bug fixes
- [ ] Deploy to production

---

## Performance Targets

### Sync Performance

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Full sync (10k records) | 10s | 0.5s | 20x faster |
| Payload size | 10MB | 50KB | 200x smaller |
| Incremental sync | N/A | 0.1s | N/A |

### Insights Performance

| Endpoint | Target | With Cache |
|----------|--------|------------|
| Daily summary | <100ms | <10ms |
| Top sites | <150ms | <20ms |
| Recent activity | <200ms | <30ms |
| Productivity hours | <150ms | <25ms |

### Data Quality

| Metric | Target |
|--------|--------|
| Valid data | >99% |
| Health score | >95% |
| Test coverage | >95% |

---

## Testing Commands

```bash
# Run all Phase 2 tests
bundle exec rspec spec/models/sync_log_spec.rb
bundle exec rspec spec/services/data_sync_service_spec.rb
bundle exec rspec spec/services/data_sanitizer_service_spec.rb
bundle exec rspec spec/services/insights/
bundle exec rspec spec/requests/data_sync_spec.rb
bundle exec rspec spec/requests/insights_spec.rb

# Check coverage
COVERAGE=true bundle exec rspec

# Lint
bundle exec rubocop

# Security scan
bundle exec brakeman

# Full quality check
make quality-check
```

---

## Manual Testing

### Test Incremental Sync

```bash
# First sync (all data)
curl -X POST http://localhost:3001/api/v1/data/sync \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"pageVisits": [...], "tabAggregates": [...]}'

# Second sync (only new data)
curl -X POST http://localhost:3001/api/v1/data/sync \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"pageVisits": [...], "since": "2025-10-18T10:00:00Z"}'

# Check sync status
curl http://localhost:3001/api/v1/data/sync/status \
  -H "Authorization: Bearer $TOKEN"
```

### Test Insights APIs

```bash
# Daily summary
curl "http://localhost:3001/api/v1/insights/daily_summary?date=2025-10-18" \
  -H "Authorization: Bearer $TOKEN"

# Top sites
curl "http://localhost:3001/api/v1/insights/top_sites?period=week&limit=10" \
  -H "Authorization: Bearer $TOKEN"

# Recent activity
curl "http://localhost:3001/api/v1/insights/recent_activity?limit=20" \
  -H "Authorization: Bearer $TOKEN"

# Productivity hours
curl "http://localhost:3001/api/v1/insights/productivity_hours?period=week" \
  -H "Authorization: Bearer $TOKEN"
```

### Test Health Checks

```bash
# System health
curl http://localhost:3001/api/v1/health

# Data quality
curl http://localhost:3001/api/v1/health/data_quality \
  -H "Authorization: Bearer $TOKEN"
```

---

## Common Issues & Solutions

### Issue: Sync Conflicts Not Resolving

**Symptom:** Newer data being overwritten by older data

**Solution:** Check conflict resolution logic in `DataSyncService#resolve_page_visit_conflict`

```ruby
# Verify max duration is being used
expect(merged[:duration_seconds]).to eq([existing.duration_seconds, new.duration_seconds].max)
```

---

### Issue: Insights Returning Empty Data

**Symptom:** All insights endpoints return 0 counts

**Solution:** Check if data exists and filters are correct

```bash
# Check if data exists
rails console
PageVisit.where(user_id: 1).count

# Check date filters
PageVisit.where(user_id: 1).where('visited_at >= ?', 7.days.ago).count
```

---

### Issue: Slow Insights Queries

**Symptom:** Insights APIs taking >1 second

**Solution:** Add missing database indexes

```ruby
# Check query plan
PageVisit.where(user_id: 1).where('visited_at >= ?', 7.days.ago).explain

# Add indexes if needed
add_index :page_visits, [:user_id, :visited_at]
add_index :page_visits, [:user_id, :domain]
```

---

## Next Steps After Phase 2

**After completing Phase 2:**

1. ✅ Verify all tests pass
2. ✅ Deploy to production
3. ✅ Monitor sync performance (should be 20x faster)
4. ✅ Monitor data quality (should be >99%)
5. ✅ Collect user feedback on insights
6. ⏭️ **Proceed to Phase 3: Pattern Detection**
   - Hoarder tabs
   - Serial openers
   - Research sessions
   - Reading list

---

## FAQ

**Q: Can I skip Week 2 (data quality) to save time?**
A: No. Bad data will break Phase 3 pattern detection. Data quality is critical.

**Q: Do I need to update the browser extension?**
A: Yes, for incremental sync. But it's backward compatible (extension can still send all data).

**Q: Can I add encryption in Phase 2?**
A: Not recommended. Focus on MVP first. Add encryption before public launch (see phase-2/mvp-first-vs-security-first.md).

**Q: How do I test with production-like data?**
A: Use `db/seeds.rb` to generate test data, or copy anonymized data from production.

**Q: What if I find a critical bug during Week 4?**
A: Don't deploy! Fix bug, add regression test, re-test everything.

---

## Resources

### Internal Docs
- [Phase 1 Requirements](../phase-1/) (already complete)
- [Phase 3 Requirements](../phase-3/) (pattern detection - next)
- [Codebase Style Guide](../../CLAUDE.md)

### External Docs
- [Rails ActiveRecord Validations](https://guides.rubyonrails.org/active_record_validations.html)
- [RSpec Best Practices](https://www.betterspecs.org/)
- [PostgreSQL Performance Tips](https://wiki.postgresql.org/wiki/Performance_Optimization)

---

## Support

**Questions?** Check:
1. Read the relevant document first
2. Check code comments
3. Search existing tests for examples
4. Ask in team chat

**Found a bug?**
1. Add a failing test
2. Fix the bug
3. Ensure test passes
4. Commit with clear message

---

**Status:** Ready for Implementation
**Last Updated:** 2025-10-18
**Next:** Begin Week 1 - Sync Optimization

---

## Summary

Phase 2 makes your sync endpoint **20x faster** and adds **basic insights** to validate data quality before Phase 3 pattern detection.

**Start here:** Read `00-phase-2-overview.md` then follow the week-by-week plan in `04-implementation-timeline.md`.

Good luck! 🚀
