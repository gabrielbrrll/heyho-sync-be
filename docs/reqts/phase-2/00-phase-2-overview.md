# Phase 2: Sync Optimization & Basic Insights

## Overview

**Goal:** Optimize the sync endpoint and add basic browsing insights before building Phase 3 patterns.

**Why Phase 2 First:**
- Current sync endpoint works but has optimization opportunities
- Basic insights validate data quality
- Lays foundation for Phase 3 pattern detection
- Faster MVP to validate product-market fit

**Timeline:** 3-4 weeks

---

## Current State Analysis

### What's Working ✅

**Current Implementation:**
- ✅ Data sync endpoint (`POST /api/v1/data/sync`)
- ✅ Browsing data retrieval (`GET /api/v1/browsing_data`)
- ✅ JWT authentication
- ✅ Service-to-service authentication
- ✅ Pagination support
- ✅ Schema validation (JSONSchemer)
- ✅ Upsert logic (deduplication)
- ✅ Transaction safety
- ✅ Flexible format transformation (camelCase ↔ snake_case)

**Current Performance:**
- ✅ Handles individual page visits
- ✅ Deduplicates by ID
- ✅ Validates timestamps
- ✅ Extracts domains

---

## Current Issues & Optimization Opportunities

### 1. Performance Issues ⚠️

**Problem: N+1 Sync Requests**
```javascript
// Browser extension currently does this:
pageVisits.forEach(visit => {
  await api.sync({ pageVisits: [visit] })  // ❌ 100 requests for 100 visits!
})
```

**Solution: Batch Sync**
```javascript
// Should do this:
await api.sync({
  pageVisits: pageVisits,  // ✅ 1 request for 100 visits
  tabAggregates: tabAggregates
})
```

**Impact:**
- Current: 100 requests × 200ms = 20 seconds
- Optimized: 1 request × 500ms = 0.5 seconds
- **40x faster!**

---

### 2. Missing Incremental Sync 🔄

**Problem: Always Syncs Everything**

Currently, extension sends all data on every sync:
```javascript
// ❌ Sends 10,000 page visits every time
await api.sync({
  pageVisits: allPageVisits  // Inefficient!
})
```

**Solution: Send Only New/Updated Data**
```javascript
// ✅ Send only changes since last sync
const lastSyncTime = localStorage.getItem('lastSyncTime')
const newVisits = pageVisits.filter(v => v.visited_at > lastSyncTime)

await api.sync({
  pageVisits: newVisits,
  since: lastSyncTime
})

localStorage.setItem('lastSyncTime', Date.now())
```

**Impact:**
- Current: 10,000 records × 1KB = 10MB payload
- Optimized: 50 records × 1KB = 50KB payload
- **200x smaller!**

---

### 3. No Conflict Resolution ⚠️

**Problem: Last Write Wins (Dangerous)**

Current upsert logic:
```ruby
PageVisit.upsert_all(visits_params, unique_by: :id)
# ↑ Blindly overwrites existing data
```

**Scenario:**
1. Device A syncs: `{ id: '123', duration: 60 }`
2. Device B syncs (offline data): `{ id: '123', duration: 30 }`
3. Result: Device B overwrites A's data ❌

**Solution: Smart Merge**
```ruby
# Prefer newer data (by timestamp)
# OR merge fields (sum durations, max engagement)
```

---

### 4. No Sync Status Tracking 📊

**Problem: No Way to Know What's Synced**

Users can't see:
- When was last sync?
- How many items synced?
- Are there sync errors?
- Is sync in progress?

**Solution: Add sync metadata**
```ruby
create_table :sync_logs do |t|
  t.references :user
  t.datetime :synced_at
  t.integer :page_visits_synced
  t.integer :tab_aggregates_synced
  t.string :status  # 'success', 'failed', 'partial'
  t.jsonb :errors
end
```

---

### 5. No Data Validation on Read ⚠️

**Problem: Corrupt Data Can Crash Frontend**

Current GET endpoint returns raw data:
```ruby
@page_visits.as_json  # No validation!
```

If database has corrupt data:
- `duration_seconds = -999999`
- `engagement_rate = 5.0` (should be 0-1)
- `visited_at = NULL`

Frontend crashes trying to render this.

**Solution: Add data sanitization**

---

### 6. Missing Insights Endpoints 📈

**Problem: No Way to Get Aggregated Data**

Currently, clients must:
1. Fetch all page_visits
2. Calculate insights client-side
3. Waste bandwidth and CPU

**Solution: Add server-side insights**
- `GET /api/v1/insights/daily_summary`
- `GET /api/v1/insights/top_sites`
- `GET /api/v1/insights/recent_activity`

---

## Phase 2 Scope

### Week 1: Sync Optimization

**Goals:**
1. Add incremental sync (only send changes)
2. Add batch size limits (prevent huge payloads)
3. Add conflict resolution (smart merge)
4. Add sync logging (track sync history)

**Deliverables:**
- Updated `DataSyncService` with incremental sync
- New `SyncLog` model
- Updated API response with sync metadata
- Extension changes to support incremental sync

---

### Week 2: Data Quality & Validation

**Goals:**
1. Add data sanitization on read
2. Add data validation on write (stricter)
3. Add background job to fix corrupt data
4. Add health check endpoint

**Deliverables:**
- `DataSanitizer` service
- `DataValidator` service
- Background job: `CleanupCorruptDataJob`
- Health check endpoint: `GET /api/v1/health`

---

### Week 3: Basic Insights APIs

**Goals:**
1. Daily/weekly summary
2. Top sites by domain
3. Recent activity timeline
4. Basic productivity metrics

**Deliverables:**
- `GET /api/v1/insights/daily_summary`
- `GET /api/v1/insights/weekly_summary`
- `GET /api/v1/insights/top_sites`
- `GET /api/v1/insights/recent_activity`

---

### Week 4: Polish & Testing

**Goals:**
1. Performance benchmarks
2. Integration tests
3. API documentation
4. Browser extension updates

**Deliverables:**
- RSpec tests (95%+ coverage)
- API docs (Swagger/OpenAPI)
- Performance benchmarks
- Updated extension with new APIs

---

## Success Metrics

### Performance
- ✅ Sync time: <500ms for 100 records
- ✅ Incremental sync: <100ms for 10 records
- ✅ API response time: <200ms (p95)
- ✅ Database queries: <5 per request

### Reliability
- ✅ Sync success rate: >99%
- ✅ Data corruption rate: <0.1%
- ✅ Conflict resolution accuracy: >95%

### Data Quality
- ✅ Valid timestamps: 100%
- ✅ Valid domains: >99%
- ✅ Valid engagement rates: 100% (0-1 range)
- ✅ No NULL required fields

---

## Out of Scope (Phase 3)

**Defer to Phase 3:**
- ❌ Hoarder tabs detection
- ❌ Serial openers detection
- ❌ Research sessions
- ❌ Reading list
- ❌ Pattern-based insights

**Why:** Focus on sync optimization first, patterns later.

---

## Dependencies

**Required:**
- ✅ Phase 1 (Auth, data models) - DONE
- ✅ PostgreSQL with JSONB support - DONE
- ✅ Rails 7 with ActiveRecord - DONE

**Optional:**
- ⏭️ Redis (for caching) - Can add later
- ⏭️ Background jobs (Sidekiq) - Can use ActiveJob with async adapter

---

## Risks & Mitigations

### Risk 1: Breaking Changes to Extension

**Risk:** Sync optimization breaks existing extension

**Mitigation:**
- Support both old and new formats during transition
- Add feature flags
- Version the API (`/api/v1` vs `/api/v2`)

---

### Risk 2: Data Migration Issues

**Risk:** Corrupt data breaks migration

**Mitigation:**
- Run data quality check BEFORE migration
- Create backup before changes
- Add rollback plan

---

### Risk 3: Performance Regression

**Risk:** Optimizations make things slower

**Mitigation:**
- Benchmark before/after
- Load test with real data (10k+ records)
- Monitor in production

---

## Phase 2 Documents

**Created Documents:**
1. `00-phase-2-overview.md` (this file)
2. `01-sync-optimization.md` - Incremental sync, batching, conflicts
3. `02-data-quality.md` - Validation, sanitization, cleanup
4. `03-insights-apis.md` - Basic insights endpoints
5. `04-api-specification.md` - Updated API docs
6. `05-implementation-plan.md` - Week-by-week tasks
7. `06-testing-strategy.md` - RSpec tests, benchmarks
8. `README.md` - Quick reference

---

## Next Steps

1. ✅ Review this overview
2. ⏭️ Read detailed implementation docs (01-06)
3. ⏭️ Approve Phase 2 scope
4. ⏭️ Start Week 1: Sync optimization

---

**Status:** Planning
**Priority:** High (before Phase 3)
**Estimated Effort:** 80-100 hours (3-4 weeks)
**Dependencies:** Phase 1 complete ✅

---

## Comparison: Phase 2 vs. Phase 3

| Aspect | Phase 2 (This) | Phase 3 (Later) |
|--------|----------------|-----------------|
| **Focus** | Sync optimization, data quality | Pattern detection, smart features |
| **Complexity** | Medium (infrastructure) | High (algorithms, ML) |
| **Timeline** | 3-4 weeks | 4-5 weeks |
| **User Value** | Faster sync, reliable data | Smart insights, productivity hacks |
| **Technical Debt** | Pays down debt | Builds on solid foundation |
| **Risk** | Low (incremental improvements) | Medium (new features) |

**Why Phase 2 First:**
- Faster sync = better UX immediately
- Clean data = Phase 3 patterns work better
- Insights API = validate data quality
- Lower risk = confidence for Phase 3

---

**Ready to proceed?** Review `01-sync-optimization.md` for detailed implementation.
