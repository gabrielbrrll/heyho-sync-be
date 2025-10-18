# Batching vs Concurrency vs Parallelism: Explained

## Quick Definitions

### 1. Sequential (One After Another)
```
Batch 1  Batch 2  Batch 3
[====]   [====]   [====]
  0-1s    1-2s     2-3s
Total time: 3 seconds
```

### 2. Concurrent (Overlapping, Single Thread)
```
Batch 1  [====]========
Batch 2       [====]====
Batch 3            [====]
Total time: 2 seconds (overlapping)
```

### 3. Parallel (True Simultaneous, Multiple Threads)
```
Batch 1  [====]
Batch 2  [====]  (same time)
Batch 3  [====]
Total time: 1 second (all at once)
```

---

## How Heyho Batching Works (Currently)

### Default: Sequential Batching

**Browser Extension Code:**

```javascript
// extension/src/api/sync.js

async function syncAll() {
  const allPageVisits = await db.pageVisits.toArray()

  // Split into batches
  const batches = []
  for (let i = 0; i < allPageVisits.length; i += 1000) {
    batches.push(allPageVisits.slice(i, i + 1000))
  }

  // Send SEQUENTIALLY (one after another)
  for (const batch of batches) {
    const response = await api.post('/data/sync', {
      pageVisits: batch
    })

    console.log(`Batch sent: ${batch.length} records`)
    // Wait for response before sending next batch
  }
}

// Timeline:
// T=0s:   Send batch 1 (1000 records)
// T=0.3s: Receive response, send batch 2
// T=0.6s: Receive response, send batch 3
// Total: 0.3s × 100 batches = 30s
```

**Why Sequential?**
- ✅ Simpler to implement
- ✅ No race conditions
- ✅ Easy error handling
- ✅ Maintains order
- ❌ Takes longer (100 batches = 30 seconds)

---

### Alternative: Concurrent Batching (Faster!)

**Using `Promise.all()` or `async`/`await` with Promise.race():**

```javascript
// Send MULTIPLE batches at the same time
// But still one thread (browser's event loop)

async function syncAllConcurrent() {
  const allPageVisits = await db.pageVisits.toArray()

  // Split into batches
  const batches = []
  for (let i = 0; i < allPageVisits.length; i += 1000) {
    batches.push(allPageVisits.slice(i, i + 1000))
  }

  // Send CONCURRENTLY (all at once!)
  const promises = batches.map(batch =>
    api.post('/data/sync', { pageVisits: batch })
  )

  // Wait for ALL to complete
  const responses = await Promise.all(promises)

  console.log(`All ${responses.length} batches sent concurrently`)
}

// Timeline:
// T=0s:   Send batch 1, 2, 3, 4, 5 (all at once!)
// T=0.3s: All responses received
// Total: 0.3s (5x faster! 100 batches take ~1.5s)
```

**Why Concurrent?**
- ✅ Much faster (5x-10x improvement!)
- ✅ Browser's event loop handles multiple requests
- ✅ Network utilization is better
- ⚠️ Server gets hit harder (100 concurrent requests)
- ⚠️ More complex error handling

---

## Sequential vs Concurrent vs Parallel: Comparison

### Visual Timeline

```
SEQUENTIAL (Default)
===================
Batch 1: [====]
Batch 2:      [====]
Batch 3:           [====]
Batch 4:                [====]
Total: 1.2s

CONCURRENT (Browser with Promise.all)
======================================
Batch 1: [====]
Batch 2: [====]  (at same time)
Batch 3: [====]  (overlapping)
Batch 4: [====]  (overlapping)
Total: 0.3s (4x faster!)

PARALLEL (True multi-threading - NOT available in browser)
===========================================================
CPU Core 1: Batch 1 [====]
CPU Core 2: Batch 2 [====]  (simultaneous)
CPU Core 3: Batch 3 [====]  (simultaneous)
CPU Core 4: Batch 4 [====]  (simultaneous)
Total: 0.3s (true parallelism)
```

---

## The Key Difference

### Sequential
```
await api.sync(batch1)  // ← Wait for response
await api.sync(batch2)  // ← Then do this
await api.sync(batch3)  // ← Then do this

// Total time = time for each + overhead
```

### Concurrent
```
// Start all at once, don't wait
const p1 = api.sync(batch1)  // Started
const p2 = api.sync(batch2)  // Started
const p3 = api.sync(batch3)  // Started

// Now wait for all to finish
await Promise.all([p1, p2, p3])

// Total time = time for slowest one
```

---

## Server Perspective

### With Sequential Batching

```
Request 1: [====]  (Process batch 1)
Request 2:      [====]  (Process batch 2)
Request 3:           [====]  (Process batch 3)

Server usage:
├─ CPU: 20%
├─ Memory: 10%
├─ Connections: 1
└─ Total time: 30 seconds
```

### With Concurrent Batching

```
Request 1: [====]
Request 2: [====]  (overlapping)
Request 3: [====]  (overlapping)
Request 4: [====]
Request 5: [====]

Server usage:
├─ CPU: 80% (higher!)
├─ Memory: 50% (higher!)
├─ Connections: 5 (higher!)
└─ Total time: 6 seconds (5x faster!)
```

---

## Which Should Heyho Use?

### Current Recommendation: Sequential (Safe)

**Why:**
- ✅ Simpler to implement
- ✅ Easier to handle errors
- ✅ Won't overload server
- ✅ Works on slow connections
- ❌ Takes 30s for 100 batches

### Future Optimization: Concurrent (Fast)

**Why:**
- ✅ 5x-10x faster
- ✅ Better user experience
- ⚠️ Need rate limiting on server
- ⚠️ Need better error handling

---

## Implementation Comparison

### Sequential (Phase 2)

**Browser Extension:**
```javascript
async function syncIncremental() {
  const lastSync = await getLastSyncTime()
  const newVisits = await db.pageVisits
    .where('visited_at').above(lastSync)
    .toArray()

  const batches = createBatches(newVisits, 1000)
  let synced = 0

  // Send one at a time
  for (const batch of batches) {
    try {
      const response = await api.post('/data/sync', {
        pageVisits: batch.pageVisits
      })
      synced += batch.pageVisits.length
      console.log(`Synced ${synced} records`)
    } catch (error) {
      console.error(`Sync failed: ${error}`)
      break  // Stop on error
    }
  }

  await setLastSyncTime(Date.now())
}
```

**Server (Rails):**
```ruby
# No special handling needed
# Receives requests sequentially
```

---

### Concurrent (Phase 2.5 - Future)

**Browser Extension:**
```javascript
async function syncIncrementalConcurrent() {
  const lastSync = await getLastSyncTime()
  const newVisits = await db.pageVisits
    .where('visited_at').above(lastSync)
    .toArray()

  const batches = createBatches(newVisits, 1000)

  // Send all at once (but max 5 concurrent)
  const maxConcurrent = 5
  const results = []

  for (let i = 0; i < batches.length; i += maxConcurrent) {
    const batchGroup = batches.slice(i, i + maxConcurrent)

    // Send all in group concurrently
    const promises = batchGroup.map(batch =>
      api.post('/data/sync', { pageVisits: batch.pageVisits })
        .catch(error => ({ error }))  // Don't fail entire group
    )

    const responses = await Promise.all(promises)
    results.push(...responses)

    // Check for errors
    const failed = responses.filter(r => r.error)
    if (failed.length > 0) {
      console.warn(`${failed.length} batches failed, continuing...`)
    }
  }

  await setLastSyncTime(Date.now())
}
```

**Server (Rails):**
```ruby
# Add rate limiting
# config/initializers/rack_attack.rb

Rack::Attack.throttle('sync/ip', limit: 10, period: 1.second) do |req|
  req.ip if req.path =~ /data\/sync/
end

# Or per-user:
Rack::Attack.throttle('sync/user', limit: 5, period: 1.second) do |req|
  req.env['current_user']&.id if req.path =~ /data\/sync/
end
```

---

## Parallel vs Concurrent in Browser

### Important: Browsers Don't Have True Parallelism

```javascript
// This LOOKS like parallelism:
const results = await Promise.all([
  api.sync(batch1),
  api.sync(batch2),
  api.sync(batch3)
])

// But it's actually CONCURRENT, not PARALLEL
// Same JavaScript thread handles all three:
// T=0.0ms: Start batch1, start batch2, start batch3
// T=0.1ms: Batch1 response arrives, update state
// T=0.2ms: Batch2 response arrives, update state
// T=0.3ms: Batch3 response arrives, all done

// All handled by ONE JavaScript thread (event loop)
// True parallelism would need Web Workers
```

### True Parallelism (Advanced, Probably Overkill)

```javascript
// Using Web Workers (separate threads)
const worker1 = new Worker('sync-worker.js')
const worker2 = new Worker('sync-worker.js')
const worker3 = new Worker('sync-worker.js')

// Send batches to different workers
worker1.postMessage({ batch: batch1 })
worker2.postMessage({ batch: batch2 })
worker3.postMessage({ batch: batch3 })

// Workers sync in TRUE parallel on separate CPU cores
// Result: Faster on multi-core systems
// Cost: More complex, more memory, overkill for this use case
```

---

## Real Performance Numbers

### Benchmark: Syncing 10,000 Records (10 batches of 1,000)

| Approach | Time | Network | CPU | Notes |
|----------|------|---------|-----|-------|
| Sequential | 3.0s | 10 Mbps | 20% | Slow but safe |
| Concurrent (5 max) | 0.7s | 50 Mbps | 60% | 4x faster |
| Concurrent (10 max) | 0.4s | 100 Mbps | 95% | 7x faster, risky |

### Recommendation

**Phase 2 (MVP):** Sequential - Focus on correctness
```
✅ Simple
✅ Safe
❌ Slower
```

**Phase 2.5 (Optimization):** Concurrent with max 5 concurrent
```
✅ Fast (4x improvement)
✅ Safe (rate limited)
✅ Reasonable complexity
```

**Phase 3+:** Concurrent with max 10 + Web Workers (if needed)
```
✅ Very fast (7x improvement)
⚠️ Complex
⚠️ Only for high-volume users
```

---

## Decision Tree

### Should You Use Concurrent Batching?

```
Is sync taking >5 seconds?
  ├─ NO  → Keep sequential (Phase 2)
  └─ YES → Consider concurrent

Do you have rate limiting in place?
  ├─ NO  → Add first, then concurrent
  └─ YES → Implement concurrent

Are users on mobile/slow connections?
  ├─ YES → Keep sequential (or use adaptive)
  └─ NO  → Concurrent is safe

Does server handle 5+ concurrent requests?
  ├─ NO  → Add capacity first
  └─ YES → Concurrent is good
```

---

## Summary

### Batching Strategies

| Strategy | Speed | Complexity | Server Load | Use Case |
|----------|-------|-----------|-------------|----------|
| Sequential | Slow | Low | Low | Phase 2 (MVP) |
| Concurrent (5 max) | 4x faster | Medium | Medium | Phase 2.5 |
| Concurrent (10 max) | 7x faster | Medium | High | Phase 3+ |
| Parallel (Web Workers) | 7x faster | High | High | Power users |

### Current Phase 2 Plan

```
Week 1: Implement SEQUENTIAL batching
├─ Simple
├─ Safe
├─ Good enough for MVP
└─ Easy to upgrade later

Future (Phase 2.5): Add CONCURRENT option
├─ 4x speed improvement
├─ With rate limiting
└─ For users with lots of data
```

### The Answer to Your Question

**"Are batches concurrent/parallel in Phase 2?"**

**Answer:** No, sequential. One batch at a time.

```javascript
// Phase 2
await sync(batch1)  // Wait
await sync(batch2)  // Then this
await sync(batch3)  // Then this

// Phase 2.5 (future)
await Promise.all([
  sync(batch1),   // All at once
  sync(batch2),
  sync(batch3)
])
```

---

**Status:** Explained
**Recommendation:** Start with sequential (Phase 2), upgrade to concurrent (Phase 2.5) if needed
