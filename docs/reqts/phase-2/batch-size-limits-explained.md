# Batch Size Limits: Why They Matter

## The Problem Scenario

### What Happens Without Limits

**Imagine this:**

```javascript
// Browser extension has been running for 3 months
// Accumulated 100,000 browsing records in local IndexedDB

// Extension tries to sync everything at once:
await api.sync({
  pageVisits: [
    { id: '1', url: '...', ... },
    { id: '2', url: '...', ... },
    // ... 99,998 more records ...
    { id: '100000', url: '...', ... }
  ]
})
```

### What Happens on the Server

**Step 1: Receive Request**
```
POST /api/v1/data/sync
Content-Length: 500MB  ← Huge!

Rails receives entire 500MB payload into memory
```

**Step 2: Parse JSON**
```ruby
# Rails.request.body → 500MB JSON string
# JSON.parse → 500MB Ruby objects in memory

# Each record is ~5KB:
# 100,000 records × 5KB = 500MB
```

**Step 3: Validate**
```ruby
page_visits.each do |visit|
  validate(visit)  # More memory allocation
end
```

**Step 4: Database Transaction**
```ruby
ActiveRecord::Base.transaction do
  page_visits.each do |visit|
    PageVisit.create!(visit)  # 100,000 database operations!
  end
end
```

### The Problems

#### Problem #1: Memory Exhaustion ⚠️

```
Server has 2GB RAM

Request comes in: 500MB
├─ Raw payload: 500MB
├─ Parsed JSON: 500MB (temporary, before GC)
├─ Ruby objects: 500MB
├─ Database buffer: 200MB (keeping 100k records in transaction)
└─ Total: ~1.7GB

Available: 0.3GB  ← Still have 300MB, but adding more data...

During transaction, Rails holds ALL 100k records in memory!
Total memory: 1.7GB + growth = crashes!
```

**Result:**
```
ActionController::BadRequest: Request entity too large
ERROR: out of memory for query result
FATAL: server process was terminated abnormally
```

---

#### Problem #2: Request Timeout ⏱️

```
Typical HTTP timeout: 30 seconds

Timeline:
T=0s:   Request arrives
T=1s:   Parse JSON
T=2s:   Validate records
T=3s:   Start database transaction
T=15s:  Database still processing INSERT...INSERT...INSERT (100k rows)
T=30s:  TIMEOUT ❌ (Nginx/Puma timeout)

Response: 504 Gateway Timeout
Data: Partially written (transaction ROLLBACK due to timeout)
Result: Corrupted state
```

---

#### Problem #3: Transaction Too Large 📦

```sql
-- Inside PostgreSQL transaction:

BEGIN;
  INSERT INTO page_visits (...) VALUES (...);  -- Record 1
  INSERT INTO page_visits (...) VALUES (...);  -- Record 2
  -- ... 99,998 more ...
  INSERT INTO page_visits (...) VALUES (...);  -- Record 100,000
COMMIT;

-- PostgreSQL maintains transaction log:
-- Each INSERT is logged
-- 100,000 inserts = MASSIVE transaction log
-- Transaction may exceed max_allowed_packet (16MB default)

ERROR: cannot have more than 1000 locks in a transaction
ERROR: transaction too large
```

---

## The Solution: Batch Size Limits

### What Are Batch Limits?

**Simple rule:** Break large syncs into smaller chunks.

```
Without limits:
Single request: 100,000 records

With limits (max 1,000 per request):
Request 1: 1,000 records
Request 2: 1,000 records
Request 3: 1,000 records
... 100 requests total ...
Request 100: 1,000 records
```

### Implementation

```ruby
# config/settings.rb
MAX_PAGE_VISITS_PER_SYNC = 1_000
MAX_TAB_AGGREGATES_PER_SYNC = 500

class DataSyncService
  def sync
    # Check batch size FIRST
    if page_visits.size > MAX_PAGE_VISITS_PER_SYNC
      return failure(
        message: "Batch too large. Max: #{MAX_PAGE_VISITS_PER_SYNC}, Got: #{page_visits.size}"
      )
    end

    # Now safe to process
    save_batch
  end
end
```

---

## Why 1,000 Records?

### Memory Math

```
Per record: ~5KB (url, title, metadata, etc)
Max records: 1,000
Memory per sync: 1,000 × 5KB = 5MB

Safe threshold:
├─ Payload: 5MB
├─ Parsed: 5MB
├─ Transaction buffer: 2MB
├─ Rails overhead: 50MB
└─ Total: ~65MB (safe on any server)

Server with 2GB RAM:
└─ 1,000 records = 65MB = 3.25% of RAM ✅ Safe
```

### Time Math

```
1,000 records:
├─ Parse JSON: 10ms
├─ Validate: 50ms
├─ Database INSERT: 100-200ms
└─ Total: ~300ms (well under 30s timeout)

Extension can send batches rapidly:
5 batches × 200ms = 1 second total ✅ Fast
```

### Database Math

```
PostgreSQL constraints:
├─ Max locks per transaction: 64,000
├─ Max tuple size: 1.4GB
└─ Max transaction size: Unlimited (but practical: 100MB)

With 1,000 records:
└─ Each transaction is small and fast ✅ Safe
```

---

## Real-World Example

### Without Batch Limits (Bad)

```javascript
// Browser extension syncs all 100,000 records
await api.sync({
  pageVisits: allPageVisits  // 100,000 items
})

// Server response:
{
  "error": "Request entity too large",
  "status": 413
}

// Extension doesn't know what to do
// Data never syncs ❌
// User thinks extension is broken ❌
```

---

### With Batch Limits (Good)

```javascript
// Browser extension sends in chunks
const BATCH_SIZE = 1000

for (let i = 0; i < allPageVisits.length; i += BATCH_SIZE) {
  const batch = allPageVisits.slice(i, i + BATCH_SIZE)

  const response = await api.sync({
    pageVisits: batch  // 1,000 items
  })

  if (response.ok) {
    console.log(`Synced batch ${i + 1}`)
  } else {
    console.error(`Failed batch ${i + 1}: ${response.error}`)
  }
}

// All 100 batches sync successfully ✅
// Total time: ~20 seconds ✅
// No memory issues ✅
```

---

## What Happens When You Hit the Limit?

### Server Response

```json
{
  "success": false,
  "message": "Batch size exceeded. Max: 1000 page_visits, 500 tab_aggregates.",
  "errors": {
    "page_visits": {
      "received": 100000,
      "max": 1000
    }
  },
  "status": 413  // Payload Too Large
}
```

### Extension Should Handle It

```javascript
if (response.status === 413) {
  // Batch size exceeded, split into smaller chunks
  const SMALLER_BATCH = 500

  for (let i = 0; i < data.length; i += SMALLER_BATCH) {
    const smallerBatch = data.slice(i, i + SMALLER_BATCH)
    await api.sync({ pageVisits: smallerBatch })
  }
}
```

---

## Common Batch Sizes in Industry

### Different Services

| Service | Batch Size | Use Case |
|---------|-----------|----------|
| Elasticsearch | 100-1000 | Bulk indexing |
| AWS Lambda | 100-1000 | Batch events |
| Segment | 500 | Analytics events |
| Stripe | 100-1000 | Billing operations |
| **Heyho** | **1000** | Sync operations |

### Why These Sizes?

**Trade-off between:**
1. **Throughput** (more batches = slower overall)
2. **Safety** (smaller batches = safer per request)
3. **Latency** (fewer requests = lower latency)

```
100 records:    ✅ Super safe, ❌ 1000 requests (slow)
1,000 records:  ✅ Safe, ✅ 100 requests (good balance)
10,000 records: ⚠️ Risky, ✅ 10 requests (fast)
100,000 records: ❌ Crashes, ✅ 1 request (too risky)
```

---

## Real Scenario: What Could Go Wrong?

### Scenario: Mobile User Syncing Large Backlog

**Setup:**
- User hasn't synced in 1 month
- 50,000 page visits accumulated
- On 4G mobile (slow connection)

**Without Batch Limits:**

```
User opens extension:
"Syncing..."
[====                    ] 10%
"This is taking a while..."
[========                ] 20%
*connection drops*
"Sync failed"
❌ All 50,000 records lost
❌ No retry logic possible
❌ User frustrated
```

**With Batch Limits:**

```
User opens extension:
"Syncing..."
[=====                   ] 5% (batch 1 of ~50)
"Syncing..."
[==                      ] 2% (batch 2)
*connection drops*
✅ 1,000 records already synced!
✅ Retry picks up from batch 2
✅ Eventually all 50,000 synced
✅ User happy
```

---

## Implementation Checklist

### Server-Side (Backend)

```ruby
# ✅ Add validation
MAX_PAGE_VISITS_PER_SYNC = 1_000

if page_visits.size > MAX_PAGE_VISITS_PER_SYNC
  return error("Batch size exceeded")
end

# ✅ Return helpful error
{
  message: "Batch size exceeded",
  received: page_visits.size,
  max: MAX_PAGE_VISITS_PER_SYNC
}
```

### Client-Side (Extension)

```javascript
// ✅ Batch data before sending
const BATCH_SIZE = 1000
for (let i = 0; i < allData.length; i += BATCH_SIZE) {
  const batch = allData.slice(i, i + BATCH_SIZE)
  await api.sync({ pageVisits: batch })
}

// ✅ Handle batch-too-large error
if (response.status === 413) {
  const SMALLER = 500
  // Retry with smaller batch
}

// ✅ Show progress
console.log(`Synced ${current}/${total} records`)
```

### Testing

```ruby
# ✅ Test that large batch is rejected
it 'rejects batches exceeding max size' do
  too_many = build_list(:page_visit, 1001)
  result = DataSyncService.sync(user: user, page_visits: too_many)

  expect(result.success?).to be false
  expect(result.message).to include('Batch size exceeded')
end

# ✅ Test that max batch works
it 'accepts batch of exactly max size' do
  exact_max = build_list(:page_visit, 1000)
  result = DataSyncService.sync(user: user, page_visits: exact_max)

  expect(result.success?).to be true
end
```

---

## Summary

### Problem Without Limits
```
Large sync request (100,000 records)
→ 500MB in memory
→ Request timeout (30s)
→ Transaction too large
→ Server crash
→ Data loss
```

### Solution With Limits
```
Batch size limit (1,000 records max)
→ 5MB per request
→ Fast completion (<500ms)
→ Small transactions
→ Reliable sync
→ Safe & stable
```

### The Rule

**Simple:** 1,000 records per sync = safe, fast, reliable.

---

**Status:** Explained
**Key Takeaway:** Batch limits prevent crashes and timeouts. Every API that handles data syncing uses them.
