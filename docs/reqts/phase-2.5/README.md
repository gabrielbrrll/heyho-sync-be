# Phase 2.5: Concurrent Batching (Performance Optimization)

## Quick Start

**Goal:** Make syncing 5-10x faster by sending multiple batches concurrently.

**When:** After Phase 2 is complete and stable.

**Timeline:** 1-2 weeks
**Effort:** 20-30 hours

---

## What You Get

### Before (Phase 2 - Sequential)

```
Sync 10,000 records:
Batch 1  Batch 2  Batch 3  ...  Batch 10
[====]   [====]   [====]   ...  [====]
  0-0.3s  0.3-0.6s 0.6-0.9s ... 2.7-3.0s

Total: 3 seconds
```

### After (Phase 2.5 - Concurrent)

```
Sync 10,000 records:
Group 1 (5 batches concurrent):
[====]
[====]
[====]  ← All at same time
[====]
[====]
  0-0.3s

Group 2 (5 batches concurrent):
[====]
[====]
[====]
[====]
[====]
  0.3-0.6s

Total: 0.6 seconds (5x faster!)
```

---

## What's Included

### Week 1: Server-Side (Backend)

**Add rate limiting to protect server:**
- Install Rack::Attack gem
- Configure 5 requests/second per user
- Add Redis for production
- Test rate limits

**Deliverables:**
- `config/initializers/rack_attack.rb`
- Rate limit tests
- 429 (Too Many Requests) responses

---

### Week 2: Client-Side (Browser Extension)

**Implement concurrent batching:**
- Send 5 batches at once (instead of 1)
- Add progress tracking UI
- Handle rate limiting (retry logic)
- Show estimated time remaining

**Deliverables:**
- Updated `extension/src/api/sync.js`
- Progress UI in popup
- Concurrent sync tests

---

## Documents

1. **[00-concurrent-batching-overview.md](./00-concurrent-batching-overview.md)** - Overview
2. **[01-server-rate-limiting.md](./01-server-rate-limiting.md)** - Rack::Attack setup
3. **[02-extension-concurrent-sync.md](./02-extension-concurrent-sync.md)** - Browser implementation
4. **[README.md](./README.md)** - This file

---

## Performance Improvements

| Records | Phase 2 (Sequential) | Phase 2.5 (Concurrent) | Improvement |
|---------|---------------------|------------------------|-------------|
| 1,000 (1 batch) | 0.3s | 0.3s | Same |
| 10,000 (10 batches) | 3.0s | 0.6s | **5x faster** |
| 50,000 (50 batches) | 15s | 3.0s | **5x faster** |
| 100,000 (100 batches) | 30s | 6.0s | **5x faster** |

---

## Implementation Checklist

### Server-Side (Week 1)

- [ ] Add `rack-attack` gem
- [ ] Configure rate limits (`config/initializers/rack_attack.rb`)
- [ ] Set up Redis (production only)
- [ ] Add rate limit tests
- [ ] Test manually (send 6+ requests rapidly)
- [ ] Deploy to staging
- [ ] Monitor rate limit logs

### Client-Side (Week 2)

- [ ] Update `syncManager` class
- [ ] Implement `syncBatchesConcurrent()`
- [ ] Add progress tracking
- [ ] Add retry logic for 429 errors
- [ ] Update popup UI with progress bar
- [ ] Test with real data
- [ ] Deploy extension update

---

## Testing

### Server-Side

```bash
# Test rate limiting
for i in {1..6}; do
  curl -X POST http://localhost:3001/api/v1/data/sync \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"pageVisits":[...]}' &
done
wait

# 6th request should return 429
```

### Client-Side

```javascript
// In browser console
await syncManager.sync()

// Should see:
// "Syncing batch 1..." (concurrent)
// "Syncing batch 2..." (concurrent)
// "Syncing batch 3..." (concurrent)
// "Syncing batch 4..." (concurrent)
// "Syncing batch 5..." (concurrent)
// Total: ~0.6s for 10k records
```

---

## Rate Limit Configuration

### Recommended Limits

```ruby
# config/initializers/rack_attack.rb

# General API: 300 requests / 5 minutes
throttle('req/ip', limit: 300, period: 5.minutes)

# Sync endpoint (per IP): 10 requests / second
throttle('sync/ip', limit: 10, period: 1.second)

# Sync endpoint (per user): 5 requests / second
throttle('sync/user', limit: 5, period: 1.second)
# ↑ This allows 5 concurrent batches
```

### Why 5 Concurrent?

- ✅ **Safe**: Won't overwhelm server
- ✅ **Fast**: 5x improvement
- ✅ **Balanced**: Good network utilization without spam
- ⚠️ More than 10 = risky (potential timeouts)

---

## Concurrency Modes

### Conservative (Recommended)

```javascript
const MAX_CONCURRENT = 5

// Good balance of speed and safety
// 5x faster than sequential
// Minimal risk of rate limits
```

### Aggressive (Advanced)

```javascript
const MAX_CONCURRENT = 10

// 10x faster than sequential
// Higher risk of hitting rate limits
// Only for premium users or testing
```

### Adaptive (Future - Phase 3)

```javascript
// Start with 5
// If successful: increase to 7, then 10
// If rate limited: decrease to 3, then 2
// Auto-adjusts based on network conditions
```

---

## Error Handling

### Rate Limit (429)

```javascript
// Extension automatically retries
if (error.response?.status === 429) {
  const retryAfter = error.response.data.retry_after || 1
  await sleep(retryAfter * 1000)
  return syncBatch(batch, retries - 1)  // Retry
}
```

### Network Error

```javascript
// Fails gracefully, continues with next batch
catch (error) {
  console.error('Batch failed:', error)
  return { success: false, error }
}
```

### Partial Success

```
Syncing 10 batches:
✅ Batch 1-3: Success
❌ Batch 4: Network error
✅ Batch 5-10: Success

Result: 9/10 batches synced
User sees: "Sync partially complete (9/10)"
Can retry failed batch later
```

---

## Common Issues

### Issue: All Batches Hitting Rate Limit

**Symptom:** Every batch returns 429

**Cause:** Server rate limit is too strict

**Solution:**
```ruby
# Increase rate limit
throttle('sync/user', limit: 10, period: 1.second)  # Was 5
```

---

### Issue: Sync Still Slow

**Symptom:** Phase 2.5 not much faster than Phase 2

**Cause:** Batches not running concurrently

**Debug:**
```javascript
// Check if Promise.all is being used
console.time('sync')
await syncBatchesConcurrent(batches, 5)
console.timeEnd('sync')

// Should be ~0.6s for 10 batches
// If ~3s, batches are running sequentially
```

---

### Issue: Server CPU Spikes

**Symptom:** Server CPU at 100% during concurrent sync

**Cause:** Too many concurrent requests

**Solution:**
```ruby
# Reduce rate limit
throttle('sync/user', limit: 3, period: 1.second)  # Was 5
```

---

## Monitoring

### Server-Side

```bash
# Check Redis for rate limit data
redis-cli KEYS "rack::attack:*"

# Monitor logs
tail -f log/production.log | grep "Rack::Attack"
```

### Client-Side

```javascript
// Extension console
chrome.storage.local.get('syncStats', result => {
  console.log('Last sync duration:', result.syncStats.lastDuration)
  console.log('Average sync time:', result.syncStats.avgDuration)
})
```

---

## Rollback Plan

### If Phase 2.5 Causes Issues

**Quick rollback:**

1. **Server-side:** Disable rate limiting
```ruby
# config/initializers/rack_attack.rb
# Comment out all throttles temporarily
```

2. **Client-side:** Revert to sequential
```javascript
// In extension
const MAX_CONCURRENT = 1  // Back to sequential
```

3. **Deploy:** Push both changes
4. **Monitor:** Verify sync works
5. **Fix:** Debug and re-deploy Phase 2.5

---

## Success Criteria

### Performance

- [ ] 10k records sync in <1 second
- [ ] 100k records sync in <10 seconds
- [ ] 5x improvement over Phase 2

### Reliability

- [ ] >99% success rate
- [ ] Automatic retry on 429
- [ ] No data loss

### User Experience

- [ ] Progress visible in real-time
- [ ] Accurate time estimates
- [ ] Clear error messages

---

## Post-Phase 2.5

### What's Next?

**Phase 3: Pattern Detection**
- Hoarder tabs
- Serial openers
- Research sessions
- Reading list

**Future Optimizations (Phase 3+):**
- Adaptive concurrency (auto-adjust based on conditions)
- Web Workers (true parallelism)
- HTTP/2 multiplexing
- Background sync (Service Worker)

---

## FAQ

**Q: Will this break Phase 2?**
A: No, backward compatible. If rate limit hit, falls back to sequential.

**Q: Do I need Redis in development?**
A: No, use MemoryStore. Redis only needed in production.

**Q: Can I test without deploying extension?**
A: Yes, use browser console to call `syncManager.sync()` directly.

**Q: What if I have >100k records?**
A: Phase 2.5 handles it. 100k records = 100 batches = ~6 seconds.

**Q: Is 5 concurrent the best number?**
A: Yes for most cases. Can increase to 10 for power users.

---

## Summary

**Phase 2.5 = 5-10x faster syncs**

### How?
- Send 5 batches at once (instead of 1)
- Server protects itself with rate limiting
- Extension handles rate limits gracefully

### Timeline?
- Week 1: Server rate limiting
- Week 2: Extension concurrent sync
- Total: 1-2 weeks

### Worth it?
- ✅ Yes! Huge UX improvement
- ✅ Minimal risk (backward compatible)
- ✅ Easy to implement

---

**Status:** Ready for Implementation
**Dependencies:** Phase 2 complete
**Start:** After Phase 2 deployed and stable
**Next:** Read `01-server-rate-limiting.md` to begin
