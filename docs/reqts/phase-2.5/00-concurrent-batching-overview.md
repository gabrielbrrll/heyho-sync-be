# Phase 2.5: Concurrent Batching Optimization

## Overview

**Goal:** Make sync 5-10x faster with concurrent batch uploads while maintaining reliability.

**When:** After Phase 2 is complete and working reliably.

**Timeline:** 1-2 weeks

**Effort:** 20-30 hours

---

## Why Phase 2.5?

### Current State (Phase 2)

**Sequential batching:**
```
Sync 10,000 records (10 batches × 1,000)
Time: 10 batches × 300ms = 3 seconds
```

**Problem:**
- User waits 3 seconds for small syncs
- User waits 30 seconds for 100 batches
- Network is underutilized (only 1 request at a time)

---

### After Phase 2.5

**Concurrent batching:**
```
Sync 10,000 records (10 batches, 5 concurrent)
Time: 2 groups × 300ms = 0.6 seconds
5x faster! ⚡
```

**Benefits:**
- ✅ 5x-10x faster syncs
- ✅ Better network utilization
- ✅ Better user experience
- ✅ Still safe (rate limited)

---

## What's Included

### 1. Browser Extension Updates

**Add concurrent sync option:**
- Send multiple batches simultaneously
- Configurable concurrency limit (default: 5)
- Graceful error handling (continue if 1 batch fails)
- Progress tracking

### 2. Server-Side Rate Limiting

**Prevent abuse:**
- Per-user rate limits (5 requests/second)
- Per-IP rate limits (10 requests/second)
- Configurable limits
- Return 429 (Too Many Requests) when exceeded

### 3. Adaptive Batching

**Smart concurrency:**
- Start with 5 concurrent
- If errors → reduce to 3
- If slow connection → reduce to 2
- If fast → increase to 10
- Auto-adapt to conditions

### 4. Enhanced Progress Tracking

**Better UX:**
- Show progress percentage
- Show estimated time remaining
- Show current batch status
- Show retry attempts

---

## Technical Implementation

### Phase 2.5 Changes

**Week 1: Server-Side Rate Limiting**
- Add Rack::Attack configuration
- Add rate limit middleware
- Add 429 response handling
- Test rate limits

**Week 2: Browser Extension Concurrent Sync**
- Implement concurrent batch sending
- Add adaptive concurrency
- Add progress tracking UI
- Add error recovery
- Integration testing

---

## Out of Scope

**NOT in Phase 2.5:**
- ❌ Web Workers (true parallelism) - Phase 3+
- ❌ HTTP/2 multiplexing - Phase 3+
- ❌ WebSocket streaming - Phase 3+
- ❌ Background sync service worker - Phase 3+

**Why:** Focus on simple concurrent requests first. Advanced optimizations later.

---

## Success Metrics

### Performance

- Sync time: 5x-10x faster
- 10k records: 3s → 0.6s
- 100k records: 30s → 6s

### Reliability

- Success rate: >99%
- Error recovery: Automatic retry
- No data loss

### User Experience

- Progress visible
- Time estimate accurate
- Responsive UI (no blocking)

---

## Documents

1. **00-concurrent-batching-overview.md** (this file)
2. **01-server-rate-limiting.md** - Rack::Attack setup
3. **02-extension-concurrent-sync.md** - Browser implementation
4. **03-adaptive-concurrency.md** - Smart batching
5. **04-implementation-timeline.md** - Week-by-week plan

---

**Status:** Planning
**Priority:** After Phase 2 complete
**Next:** Review and approve Phase 2.5 scope
