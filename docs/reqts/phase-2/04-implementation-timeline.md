# Phase 2: Implementation Timeline

## Overview

**Total Duration:** 3-4 weeks
**Total Effort:** 80-100 hours
**Team Size:** 1 developer (you!)

---

## Week 1: Sync Optimization (20-25 hours)

### Day 1-2: Sync Logging & Incremental Sync (8 hours)

**Tasks:**
1. Create `SyncLog` model and migration
2. Update `DataSyncService` to log all syncs
3. Add `since` parameter support
4. Test incremental sync logic

**Deliverables:**
- ✅ Migration: `create_sync_logs`
- ✅ Model: `SyncLog` with validations
- ✅ Updated: `DataSyncService#sync` with logging
- ✅ Tests: `spec/models/sync_log_spec.rb`
- ✅ Tests: `spec/services/data_sync_service_spec.rb` (incremental sync)

**Commands:**
```bash
# Create migration
rails g migration CreateSyncLogs user:references sync_id:string:uniq status:string ...

# Run migration
rails db:migrate

# Run tests
bundle exec rspec spec/models/sync_log_spec.rb
bundle exec rspec spec/services/data_sync_service_spec.rb
```

---

### Day 3-4: Conflict Resolution & Batch Limits (8 hours)

**Tasks:**
1. Implement smart merge logic in `DataSyncService`
2. Add batch size validation
3. Handle conflicts (max duration, earliest timestamp)
4. Test conflict resolution scenarios

**Deliverables:**
- ✅ Updated: `DataSyncService#resolve_page_visit_conflict`
- ✅ Updated: `DataSyncService#save_page_visits_with_conflicts`
- ✅ Batch size constants and validation
- ✅ Tests: Conflict resolution specs

**Commands:**
```bash
# Run conflict resolution tests
bundle exec rspec spec/services/data_sync_service_spec.rb:50  # Conflict resolution describe block

# Test batch limits
bundle exec rspec spec/services/data_sync_service_spec.rb:80  # Batch limits describe block
```

---

### Day 5: Sync Status Endpoint & Extension Updates (4-5 hours)

**Tasks:**
1. Add `GET /api/v1/data/sync/status` endpoint
2. Update routes
3. Document API changes
4. Update browser extension (incremental sync logic)

**Deliverables:**
- ✅ Controller: `DataSyncController#status`
- ✅ Routes: Added sync status route
- ✅ Tests: `spec/requests/data_sync_spec.rb` (status endpoint)
- ✅ Docs: Updated API documentation

**Commands:**
```bash
# Test endpoint
bundle exec rspec spec/requests/data_sync_spec.rb

# Manual test
curl -H "Authorization: Bearer $TOKEN" http://localhost:3001/api/v1/data/sync/status
```

**Extension Changes (separate repo):**
```javascript
// extension/src/api/sync.js
// Add incremental sync logic (see 01-sync-optimization.md)
```

---

## Week 2: Data Quality & Validation (20-25 hours)

### Day 6-7: Model Validations (8 hours)

**Tasks:**
1. Add validations to `PageVisit` model
2. Add validations to `TabAggregate` model
3. Add sanitization callbacks
4. Write comprehensive model tests

**Deliverables:**
- ✅ Updated: `PageVisit` with validations & callbacks
- ✅ Updated: `TabAggregate` with validations & callbacks
- ✅ Tests: `spec/models/page_visit_spec.rb` (validation specs)
- ✅ Tests: `spec/models/tab_aggregate_spec.rb`

**Commands:**
```bash
# Run model tests
bundle exec rspec spec/models/page_visit_spec.rb
bundle exec rspec spec/models/tab_aggregate_spec.rb

# Check coverage
COVERAGE=true bundle exec rspec spec/models/
```

---

### Day 8-9: Data Sanitizer Service (8 hours)

**Tasks:**
1. Create `DataSanitizerService`
2. Add sanitization logic (clamp values, fix nulls)
3. Update controllers to use sanitizer
4. Test sanitization edge cases

**Deliverables:**
- ✅ Service: `DataSanitizerService`
- ✅ Updated: `BrowsingDataController#index` (use sanitizer)
- ✅ Tests: `spec/services/data_sanitizer_service_spec.rb`

**Commands:**
```bash
# Create service
touch app/services/data_sanitizer_service.rb
touch spec/services/data_sanitizer_service_spec.rb

# Run tests
bundle exec rspec spec/services/data_sanitizer_service_spec.rb
```

---

### Day 10: Cleanup Job & Health Checks (4-5 hours)

**Tasks:**
1. Create `CleanupCorruptDataJob`
2. Add health check endpoints
3. Create `DataQualityService`
4. Schedule cleanup job

**Deliverables:**
- ✅ Job: `CleanupCorruptDataJob`
- ✅ Controller: `HealthController`
- ✅ Service: `DataQualityService`
- ✅ Routes: Health endpoints
- ✅ Tests: Job and health endpoint tests

**Commands:**
```bash
# Create job
rails g job CleanupCorruptData

# Run job manually (test)
bundle exec rails runner "CleanupCorruptDataJob.perform_now"

# Test health endpoint
curl http://localhost:3001/api/v1/health
curl http://localhost:3001/api/v1/health/data_quality
```

---

## Week 3: Insights APIs (20-25 hours)

### Day 11-12: Daily/Weekly Summary Services (8 hours)

**Tasks:**
1. Create `Insights::DailySummaryService`
2. Create `Insights::WeeklySummaryService`
3. Add controller actions
4. Write service tests

**Deliverables:**
- ✅ Service: `Insights::DailySummaryService`
- ✅ Service: `Insights::WeeklySummaryService`
- ✅ Controller: `InsightsController#daily_summary`
- ✅ Controller: `InsightsController#weekly_summary`
- ✅ Tests: Service specs

**Commands:**
```bash
# Create services
mkdir -p app/services/insights
touch app/services/insights/daily_summary_service.rb
touch app/services/insights/weekly_summary_service.rb

# Run tests
bundle exec rspec spec/services/insights/
```

---

### Day 13-14: Top Sites & Recent Activity (8 hours)

**Tasks:**
1. Create `Insights::TopSitesService`
2. Create `Insights::RecentActivityService`
3. Add controller actions
4. Test with real data

**Deliverables:**
- ✅ Service: `Insights::TopSitesService`
- ✅ Service: `Insights::RecentActivityService`
- ✅ Controller: `InsightsController#top_sites`
- ✅ Controller: `InsightsController#recent_activity`
- ✅ Tests: Service specs

**Commands:**
```bash
# Test endpoints
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3001/api/v1/insights/top_sites?period=week&limit=10"

curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3001/api/v1/insights/recent_activity?limit=20"
```

---

### Day 15: Productivity Hours & Caching (4-5 hours)

**Tasks:**
1. Create `Insights::ProductivityHoursService`
2. Add caching to all insights endpoints
3. Add database indexes for performance
4. Benchmark queries

**Deliverables:**
- ✅ Service: `Insights::ProductivityHoursService`
- ✅ Migration: Add database indexes
- ✅ Caching: Added to all insights controllers
- ✅ Benchmarks: Query performance tests

**Commands:**
```bash
# Add indexes
rails g migration AddIndexesToPageVisits

# Run migration
rails db:migrate

# Benchmark
rails runner "scripts/benchmark_insights.rb"
```

---

## Week 4: Polish, Testing & Documentation (20-25 hours)

### Day 16-17: Integration Tests (8 hours)

**Tasks:**
1. Write request specs for all endpoints
2. Test error cases (401, 404, 422, 500)
3. Test edge cases (empty data, invalid params)
4. Ensure 95%+ test coverage

**Deliverables:**
- ✅ Tests: `spec/requests/data_sync_spec.rb` (complete)
- ✅ Tests: `spec/requests/insights_spec.rb` (all endpoints)
- ✅ Tests: `spec/requests/health_spec.rb`
- ✅ Coverage report: 95%+

**Commands:**
```bash
# Run all request specs
bundle exec rspec spec/requests/

# Check coverage
COVERAGE=true bundle exec rspec

# View coverage report
open coverage/index.html
```

---

### Day 18: API Documentation (4 hours)

**Tasks:**
1. Write OpenAPI/Swagger spec
2. Document all new endpoints
3. Add example requests/responses
4. Generate API docs

**Deliverables:**
- ✅ File: `docs/api/openapi.yml`
- ✅ Docs: Endpoint documentation with examples
- ✅ Postman collection (optional)

**Tools:**
- Use `rswag` gem for auto-generated Swagger docs
- Or write manually in `openapi.yml`

---

### Day 19: Performance Testing & Optimization (4 hours)

**Tasks:**
1. Load test sync endpoint (100 concurrent users)
2. Benchmark insights queries
3. Optimize slow queries
4. Add missing indexes

**Deliverables:**
- ✅ Benchmarks: Sync performance report
- ✅ Benchmarks: Insights query times
- ✅ Optimizations: Query improvements
- ✅ Migration: Additional indexes if needed

**Commands:**
```bash
# Load test sync endpoint
# (Use tool like Apache Bench or k6)
ab -n 1000 -c 100 -H "Authorization: Bearer $TOKEN" \
  http://localhost:3001/api/v1/data/sync

# Benchmark queries
rails runner "scripts/benchmark_queries.rb"
```

---

### Day 20: Final Testing & Deployment Prep (4-5 hours)

**Tasks:**
1. Run full test suite
2. Fix any remaining issues
3. Update CHANGELOG
4. Create deployment checklist
5. Tag release

**Deliverables:**
- ✅ All tests passing
- ✅ CHANGELOG updated
- ✅ Deployment checklist
- ✅ Git tag: `v2.0.0-phase2`

**Commands:**
```bash
# Run full test suite
bundle exec rspec

# Lint code
bundle exec rubocop

# Check for security issues
bundle exec brakeman

# Tag release
git tag -a v2.0.0-phase2 -m "Phase 2: Sync optimization and insights"
git push origin v2.0.0-phase2
```

---

## Daily Schedule Template

**Recommended Daily Workflow:**

```
09:00 - 10:00  Planning & review previous day
10:00 - 12:00  Implementation (2 hours focused work)
12:00 - 13:00  Break
13:00 - 15:00  Implementation (2 hours focused work)
15:00 - 15:30  Testing & manual verification
15:30 - 16:00  Documentation & code cleanup
16:00 - 17:00  Code review & git commit
```

**Tips:**
- 🍅 Use Pomodoro technique (25 min work, 5 min break)
- ✅ Commit frequently (after each completed task)
- 🧪 Test as you go (don't wait until end)
- 📝 Document while coding (not after)

---

## Checklist

### Week 1: Sync Optimization
- [ ] Create `SyncLog` model
- [ ] Add incremental sync support
- [ ] Implement conflict resolution
- [ ] Add batch size limits
- [ ] Create sync status endpoint
- [ ] Update browser extension
- [ ] Write tests (models, services, requests)
- [ ] Manual testing

### Week 2: Data Quality
- [ ] Add model validations (`PageVisit`, `TabAggregate`)
- [ ] Create `DataSanitizerService`
- [ ] Create `CleanupCorruptDataJob`
- [ ] Add health check endpoints
- [ ] Create `DataQualityService`
- [ ] Write tests (models, services, jobs)
- [ ] Run cleanup job on existing data

### Week 3: Insights APIs
- [ ] Create `DailySummaryService`
- [ ] Create `WeeklySummaryService`
- [ ] Create `TopSitesService`
- [ ] Create `RecentActivityService`
- [ ] Create `ProductivityHoursService`
- [ ] Add caching
- [ ] Add database indexes
- [ ] Write tests (services, requests)

### Week 4: Polish & Deployment
- [ ] Write integration tests
- [ ] Ensure 95%+ coverage
- [ ] Write API documentation
- [ ] Performance testing
- [ ] Optimize slow queries
- [ ] Update CHANGELOG
- [ ] Tag release
- [ ] Deploy to staging
- [ ] Manual QA
- [ ] Deploy to production

---

## Risk Mitigation

### If Running Behind Schedule

**Priority 1 (Must Have):**
- ✅ Sync logging
- ✅ Incremental sync
- ✅ Basic validations
- ✅ Daily summary API
- ✅ Top sites API

**Priority 2 (Should Have):**
- ✅ Conflict resolution
- ✅ Data sanitizer
- ✅ Weekly summary
- ✅ Recent activity

**Priority 3 (Nice to Have):**
- ⏭️ Health checks
- ⏭️ Cleanup job
- ⏭️ Productivity hours API
- ⏭️ Caching optimization

**If 1 week behind:**
- Skip Priority 3 items
- Move to Phase 2.5 (post-MVP)

---

## Success Metrics

**At End of Week 4:**

### Performance
- [ ] Sync time: <500ms for 100 records
- [ ] Insights API: <200ms response time
- [ ] Database queries: <5 per request

### Quality
- [ ] Test coverage: >95%
- [ ] No rubocop offenses
- [ ] No security issues (brakeman)
- [ ] All CI checks passing

### Functionality
- [ ] Incremental sync working
- [ ] 5 insights endpoints working
- [ ] Health checks passing
- [ ] Data quality >99%

### Documentation
- [ ] API docs complete
- [ ] README updated
- [ ] CHANGELOG updated
- [ ] Code commented

---

## Post-Phase 2 Cleanup

**After Phase 2 Complete:**

1. Review Phase 2 retrospective
2. Document lessons learned
3. Archive old code (if any)
4. Plan Phase 3 (pattern detection)
5. Celebrate! 🎉

---

**Status:** Implementation Ready
**Start Date:** TBD
**End Date:** TBD (3-4 weeks from start)
**Next:** Begin Week 1 implementation
