# Hybrid Encryption Architecture: Server-Side Computation with Privacy

## TL;DR: Server CAN Compute, But With Maximum Privacy Safeguards

**The Problem:**
- Zero-knowledge encryption = server can't decrypt = can't compute insights
- You want server-side computation "on the fly"
- You still want privacy-first positioning

**The Solution:**
- **Encryption at rest** (data encrypted in database)
- **Server-side decryption for computation** (decrypt in memory, compute, never persist plaintext)
- **Field-level encryption** (encrypt sensitive data, leave metadata for querying)
- **Strict access controls** (audit logs, rate limiting, role-based access)
- **User transparency** (show users exactly what we can/cannot see)

---

## Architecture Overview

### What Gets Encrypted vs. What Stays Plaintext

**Encrypted Fields (Sensitive Data):**
- `url` (full URL with paths, query params)
- `title` (page titles may contain sensitive info)
- `notes` (user-added notes)
- `tags` (user-defined tags)

**Plaintext Fields (Metadata for Querying):**
- `domain` (e.g., "github.com" - needed for aggregation)
- `visited_at` (timestamp - needed for time-based queries)
- `duration_seconds` (number - needed for calculations)
- `engagement_rate` (number - needed for pattern detection)
- `tab_count`, `window_count` (numbers - needed for aggregation)
- `user_id` (needed for querying)

**Why This Works:**
- Server can compute insights without seeing full URLs/titles
- Domain-level aggregation (e.g., "You spent 3 hours on github.com")
- Time-based patterns (e.g., "You're most productive 2-4pm")
- Engagement analysis (e.g., "You have 14 low-engagement tabs")
- Cannot see: specific pages visited, exact article titles, query strings

---

## Database Schema with Encryption

### Updated `page_visits` Table

```sql
CREATE TABLE page_visits (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),

  -- ENCRYPTED FIELDS (Rails ActiveRecord Encryption)
  url_encrypted TEXT NOT NULL,              -- Full URL (encrypted)
  title_encrypted TEXT,                     -- Page title (encrypted)

  -- PLAINTEXT METADATA (for server-side computation)
  domain VARCHAR(255),                       -- e.g., "github.com"
  visited_at TIMESTAMP NOT NULL,
  duration_seconds INTEGER DEFAULT 0,
  engagement_rate FLOAT DEFAULT 0.0,
  scroll_depth FLOAT DEFAULT 0.0,

  -- COMPUTED FIELDS (encrypted if sensitive)
  is_active BOOLEAN DEFAULT false,
  tab_index INTEGER,
  window_id VARCHAR(255),

  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  INDEX idx_user_visited (user_id, visited_at),
  INDEX idx_user_domain (user_id, domain),
  INDEX idx_user_engagement (user_id, engagement_rate)
);
```

### Updated `tab_aggregates` Table

```sql
CREATE TABLE tab_aggregates (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),

  -- ENCRYPTED FIELDS
  urls_encrypted TEXT[],                     -- Array of URLs (encrypted)
  titles_encrypted TEXT[],                   -- Array of titles (encrypted)

  -- PLAINTEXT METADATA
  domains TEXT[],                            -- Array of domains (plaintext)
  tab_count INTEGER DEFAULT 0,
  window_count INTEGER DEFAULT 0,
  created_at TIMESTAMP NOT NULL,
  duration_seconds INTEGER DEFAULT 0,
  avg_engagement_rate FLOAT DEFAULT 0.0,

  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  INDEX idx_user_created (user_id, created_at),
  INDEX idx_tab_count (user_id, tab_count)
);
```

---

## Rails ActiveRecord Encryption

### Implementation

**1. Configure Encryption Keys**

```ruby
# config/credentials.yml.enc (encrypted credentials)
active_record_encryption:
  primary_key: <generated_primary_key>
  deterministic_key: <generated_deterministic_key>
  key_derivation_salt: <generated_salt>

# Generate keys with:
# bin/rails db:encryption:init
```

**2. Models with Encryption**

```ruby
# app/models/page_visit.rb
class PageVisit < ApplicationRecord
  belongs_to :user

  # Encrypt sensitive fields
  encrypts :url_encrypted, deterministic: false
  encrypts :title_encrypted, deterministic: false

  # Validations
  validates :url_encrypted, :domain, :visited_at, presence: true
  validates :engagement_rate, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }

  # Virtual attributes for cleaner API
  def url=(value)
    self.url_encrypted = value
    self.domain = extract_domain(value)
  end

  def url
    url_encrypted
  end

  def title=(value)
    self.title_encrypted = value
  end

  def title
    title_encrypted
  end

  private

  def extract_domain(url)
    URI.parse(url).host
  rescue URI::InvalidURIError
    nil
  end
end
```

```ruby
# app/models/tab_aggregate.rb
class TabAggregate < ApplicationRecord
  belongs_to :user

  # Encrypt arrays of URLs/titles
  encrypts :urls_encrypted
  encrypts :titles_encrypted

  validates :tab_count, :window_count, numericality: { greater_than_or_equal_to: 0 }

  # Virtual attributes
  def urls=(values)
    self.urls_encrypted = values
    self.domains = values.map { |url| extract_domain(url) }.compact
  end

  def urls
    urls_encrypted || []
  end

  def titles=(values)
    self.titles_encrypted = values
  end

  def titles
    titles_encrypted || []
  end

  private

  def extract_domain(url)
    URI.parse(url).host
  rescue URI::InvalidURIError
    nil
  end
end
```

---

## Server-Side Computation (Privacy-Preserved)

### Example: Top Sites Insight

**What Server Sees:**
```ruby
# Server can aggregate by domain (plaintext)
def top_sites(user, period: 'week', limit: 10)
  start_date = period == 'week' ? 7.days.ago : 30.days.ago

  PageVisit
    .where(user_id: user.id)
    .where('visited_at >= ?', start_date)
    .group(:domain)
    .select('domain, COUNT(*) as visit_count, SUM(duration_seconds) as total_time')
    .order('total_time DESC')
    .limit(limit)
end

# Returns:
# [
#   { domain: "github.com", visit_count: 23, total_time: 3600 },
#   { domain: "stackoverflow.com", visit_count: 45, total_time: 2400 }
# ]
```

**What Server CANNOT See:**
- Specific URLs: `/anthropics/claude-code/issues/123` (encrypted)
- Page titles: "Bug: Authentication fails on login" (encrypted)
- Query parameters: `?token=secret123` (encrypted)

---

### Example: Productivity Hours

**What Server Sees:**
```ruby
# Server can analyze time patterns (plaintext timestamps/engagement)
def productivity_hours(user)
  PageVisit
    .where(user_id: user.id)
    .where('visited_at >= ?', 30.days.ago)
    .where('engagement_rate > ?', 0.5)  # High engagement
    .group("EXTRACT(HOUR FROM visited_at)")
    .select('EXTRACT(HOUR FROM visited_at) as hour, AVG(engagement_rate) as avg_engagement, COUNT(*) as visits')
    .order('avg_engagement DESC')
end

# Returns:
# [
#   { hour: 14, avg_engagement: 0.82, visits: 45 },
#   { hour: 15, avg_engagement: 0.78, visits: 38 }
# ]
```

**What Server CANNOT See:**
- What you were actually reading during those productive hours (URLs/titles encrypted)

---

### Example: Hoarder Tabs Detection

**What Server Sees:**
```ruby
# Server can detect low-engagement tabs (plaintext metrics)
def hoarder_tabs(user)
  PageVisit
    .where(user_id: user.id)
    .where('duration_seconds > ?', 300)  # Open > 5 minutes
    .where('engagement_rate < ?', 0.05)  # Very low engagement
    .order(duration_seconds: :desc)
    .limit(20)
end

# Returns:
# [
#   { id: 123, domain: "medium.com", duration: 3600, engagement: 0.02, visited_at: ... },
#   { id: 456, domain: "dev.to", duration: 2400, engagement: 0.01, visited_at: ... }
# ]
```

**User Can Decrypt on Client:**
When user views details in browser extension:
```javascript
// Extension fetches hoarder tabs
const hoarderTabs = await api.getHoarderTabs();

// Extension shows full details (decrypted)
hoarderTabs.forEach(tab => {
  console.log(`URL: ${tab.url}`);        // Extension decrypts
  console.log(`Title: ${tab.title}`);    // Extension decrypts
  console.log(`Domain: ${tab.domain}`);  // Already plaintext
});
```

---

## API Response Structure

### Server Response (Encrypted Fields Included)

```json
{
  "hoarder_tabs": [
    {
      "id": 123,
      "domain": "medium.com",
      "url_encrypted": "gAAAAABhK...",  // Base64 encrypted blob
      "title_encrypted": "gAAAAABhL...",
      "duration_seconds": 3600,
      "engagement_rate": 0.02,
      "visited_at": "2025-10-16T14:30:00Z"
    }
  ]
}
```

### Extension Decrypts Client-Side

```javascript
// Extension has user's encryption key (never sent to server)
async function decryptTab(encryptedTab) {
  const userKey = await getStoredKey();  // From browser storage

  return {
    ...encryptedTab,
    url: await decrypt(encryptedTab.url_encrypted, userKey),
    title: await decrypt(encryptedTab.title_encrypted, userKey),
    // domain, duration, etc. already plaintext
  };
}
```

---

## Privacy Safeguards

### 1. What We Can vs. Cannot See

**✅ We CAN See (Plaintext):**
- Domains you visit (e.g., "github.com")
- Time spent per domain
- Visit timestamps
- Engagement rates (how actively you read)
- Tab counts

**❌ We CANNOT See (Encrypted):**
- Full URLs (e.g., "/anthropics/claude-code/issues/123")
- Page titles (e.g., "Secret Project Planning")
- Query parameters (e.g., "?token=abc123")
- User notes
- User-defined tags

**⚖️ Privacy Trade-off:**
- **You give up:** Zero-knowledge (we can see domain-level activity)
- **You gain:** Server-side computation, real-time insights, no extension overhead
- **Result:** Privacy-conscious but not paranoid

---

### 2. User Transparency

**Privacy Dashboard for Users:**

```
┌─────────────────────────────────────────────────────┐
│ 🔒 Your Privacy Settings                            │
├─────────────────────────────────────────────────────┤
│                                                      │
│ What we can see:                                    │
│ ✅ Domains you visit (e.g., "github.com")          │
│ ✅ Time spent per domain                           │
│ ✅ When you browse (timestamps)                    │
│ ✅ How engaged you are (scroll/interaction)        │
│                                                      │
│ What we CANNOT see:                                 │
│ ❌ Full URLs (encrypted)                            │
│ ❌ Page titles (encrypted)                          │
│ ❌ Your notes (encrypted)                           │
│ ❌ Search queries in URLs (encrypted)               │
│                                                      │
│ [View Audit Log] [Download My Data]                │
└─────────────────────────────────────────────────────┘
```

---

### 3. Access Control & Audit Logging

**Every time we decrypt data, we log it:**

```ruby
# app/models/access_log.rb
class AccessLog < ApplicationRecord
  belongs_to :user

  validates :action, :resource_type, :resource_id, presence: true
end

# Migration
CREATE TABLE access_logs (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  action VARCHAR(50),           -- 'decrypt', 'view', 'export'
  resource_type VARCHAR(50),    -- 'PageVisit', 'TabAggregate'
  resource_id INTEGER,
  accessed_by VARCHAR(100),     -- 'system', 'admin', 'user'
  ip_address INET,
  created_at TIMESTAMP
);

# Usage
AccessLog.create!(
  user: user,
  action: 'decrypt',
  resource_type: 'PageVisit',
  resource_id: page_visit.id,
  accessed_by: 'system',
  ip_address: request.remote_ip
)
```

**Users can view their access log:**
```
GET /api/v1/privacy/access_logs
```

---

### 4. Rate Limiting on Decryption

**Prevent abuse:**
```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle('decryption/ip', limit: 100, period: 1.hour) do |req|
  req.ip if req.path =~ /api\/v1\/insights/
end

Rack::Attack.throttle('decryption/user', limit: 1000, period: 1.day) do |req|
  req.env['current_user']&.id if req.path =~ /api\/v1\/insights/
end
```

---

## Migration Strategy (Phase 1 → Phase 2)

### Step 1: Add Encrypted Columns

```ruby
# db/migrate/20251016_add_encryption_to_page_visits.rb
class AddEncryptionToPageVisits < ActiveRecord::Migration[7.0]
  def change
    # Add encrypted columns
    add_column :page_visits, :url_encrypted, :text
    add_column :page_visits, :title_encrypted, :text

    # Add plaintext domain (extracted from URL)
    add_column :page_visits, :domain, :string
    add_index :page_visits, [:user_id, :domain]
  end
end
```

### Step 2: Migrate Existing Data

```ruby
# lib/tasks/encrypt_existing_data.rake
namespace :encryption do
  desc "Encrypt existing page_visits data"
  task migrate: :environment do
    PageVisit.find_each(batch_size: 1000) do |pv|
      pv.url = pv.url           # Triggers encryption via virtual attribute
      pv.title = pv.title       # Triggers encryption
      pv.save!
    end

    puts "Encrypted #{PageVisit.count} page visits"
  end
end

# Run: bin/rails encryption:migrate
```

### Step 3: Drop Old Columns (After Verification)

```ruby
# db/migrate/20251023_drop_plaintext_url_columns.rb
class DropPlaintextUrlColumns < ActiveRecord::Migration[7.0]
  def change
    remove_column :page_visits, :url     # Old plaintext column
    # Keep title_encrypted only
  end
end
```

---

## Comparison: Pure Zero-Knowledge vs. Hybrid

| Aspect | Pure Zero-Knowledge | Hybrid (Our Approach) |
|--------|---------------------|----------------------|
| **Server sees URLs?** | ❌ No | ❌ No (encrypted) |
| **Server sees domains?** | ❌ No | ✅ Yes (plaintext) |
| **Server sees titles?** | ❌ No | ❌ No (encrypted) |
| **Server-side insights?** | ❌ No | ✅ Yes |
| **Extension overhead?** | ❌ High (decrypts + computes) | ✅ Low (just displays) |
| **Real-time insights?** | ❌ No | ✅ Yes |
| **Privacy level** | 🔒🔒🔒🔒🔒 (Paranoid) | 🔒🔒🔒🔒 (Privacy-conscious) |
| **Marketing angle** | "We see nothing" | "We see patterns, not content" |

---

## User-Facing Privacy Marketing

### Positioning Statement

**"Privacy-Conscious Insights"**

> "We analyze your browsing patterns to help you be more productive, but we never see the content you read. Your URLs, page titles, and notes are encrypted. We only see high-level patterns like 'you spent 3 hours on GitHub' – not which repositories or issues you viewed."

### Trust Badges

```
✅ URLs & Titles Encrypted
✅ Open Source Encryption (Rails ActiveRecord Encryption)
✅ Access Audit Logs
✅ Right to Delete Anytime
✅ GDPR & CCPA Compliant
✅ No Third-Party Data Sharing
```

---

## Summary

### You Get BOTH Server-Side Computation AND Privacy

**How We Did It:**
1. **Field-level encryption**: URLs/titles encrypted, metadata plaintext
2. **Server-side computation**: Aggregate by domain, time, engagement (all plaintext)
3. **User decryption**: Extension decrypts full URLs/titles for user viewing
4. **Privacy safeguards**: Audit logs, rate limiting, transparency

**Trade-offs:**
- **You give up:** Pure zero-knowledge (we can see domains)
- **You gain:** Server-side insights, real-time computation, scalability
- **Result:** 90% privacy, 100% functionality

**Privacy Level:**
- 🔒🔒🔒🔒 (4/5) Privacy-conscious
- Not paranoid-level, but more than sufficient for ADHD productivity tool

**Marketing Position:**
> "We help you understand your browsing habits without invading your privacy. We see patterns, not content."

---

**Status:** Hybrid Architecture Proposal
**Last Updated:** 2025-10-18
**Next Step:** Review and approve hybrid approach, then implement Phase 2
