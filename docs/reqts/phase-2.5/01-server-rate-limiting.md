# Phase 2.5.1: Server-Side Rate Limiting

## Overview

**Goal:** Protect server from concurrent batch spam while allowing legitimate fast syncs.

**Why:** Without rate limiting, concurrent batching could overwhelm the server.

---

## The Problem

### Before Rate Limiting

**Malicious scenario:**
```javascript
// Attacker sends 1000 concurrent requests
const attacks = Array(1000).fill().map(() =>
  api.sync({ pageVisits: bigBatch })
)
await Promise.all(attacks)

// Server receives 1000 simultaneous requests
// → Out of memory
// → Database connection pool exhausted
// → Server crashes
```

**Legitimate but problematic:**
```javascript
// User with buggy extension
setInterval(() => {
  api.sync({ pageVisits: allData })  // Syncs every second!
}, 1000)

// Server gets hammered with unnecessary requests
```

---

## The Solution: Rack::Attack

### What is Rack::Attack?

- Middleware for rate limiting
- Prevents abuse and DOS attacks
- Configurable limits
- Returns 429 (Too Many Requests)

---

## Implementation

### Step 1: Add Gem

```ruby
# Gemfile
gem 'rack-attack'

# Terminal
bundle install
```

---

### Step 2: Configure Middleware

```ruby
# frozen_string_literal: true

# config/initializers/rack_attack.rb

class Rack::Attack
  ### Configure Cache ###

  # Use Rails cache (Redis recommended for production)
  Rack::Attack.cache.store = Rails.cache

  ### Throttles (Rate Limiting) ###

  # Limit all requests by IP (prevent total spam)
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  # Limit sync endpoint by IP (10 requests per second)
  throttle('sync/ip', limit: 10, period: 1.second) do |req|
    req.ip if req.path == '/api/v1/data/sync' && req.post?
  end

  # Limit sync endpoint by authenticated user (5 concurrent batches)
  throttle('sync/user', limit: 5, period: 1.second) do |req|
    if req.path == '/api/v1/data/sync' && req.post?
      # Extract user from JWT token
      token = req.env['HTTP_AUTHORIZATION']&.sub('Bearer ', '')
      decoded = decode_token(token)
      decoded['sub'] if decoded  # User ID
    end
  end

  # Limit login attempts (prevent brute force)
  throttle('login/email', limit: 5, period: 20.minutes) do |req|
    if req.path == '/api/v1/auth/login' && req.post?
      req.params['email'].to_s.downcase.presence
    end
  end

  ### Blocklists ###

  # Block specific IPs (manual ban)
  blocklist('block bad IPs') do |req|
    # Check if IP is in banned list (Redis)
    Rack::Attack::Allow2Ban.filter(req.ip, maxretry: 10, findtime: 1.minute, bantime: 1.hour) do
      # Return true to ban, false to allow
      false  # Placeholder, add logic to check ban list
    end
  end

  ### Safelists (Whitelist) ###

  # Allow from localhost
  safelist('allow from localhost') do |req|
    req.ip == '127.0.0.1' || req.ip == '::1'
  end

  # Allow internal service calls
  safelist('allow service token') do |req|
    req.env['HTTP_X_SERVICE_TOKEN'] == ENV['SERVICE_SECRET']
  end

  ### Custom Response ###

  # Customize throttled response
  self.throttled_responder = lambda do |env|
    match_data = env['rack.attack.match_data']
    now = match_data[:epoch_time]

    headers = {
      'Content-Type' => 'application/json',
      'X-RateLimit-Limit' => match_data[:limit].to_s,
      'X-RateLimit-Remaining' => '0',
      'X-RateLimit-Reset' => (now + match_data[:period]).to_s
    }

    [
      429,
      headers,
      [{
        success: false,
        message: 'Rate limit exceeded. Please slow down.',
        retry_after: match_data[:period],
        error_code: 'RATE_LIMIT_EXCEEDED'
      }.to_json]
    ]
  end

  ### Helpers ###

  def self.decode_token(token)
    return nil if token.blank?

    Authentication::TokenService.decode_jwt_token(token)
  rescue StandardError
    nil
  end
end

# Enable Rack::Attack
Rails.application.config.middleware.use Rack::Attack
```

---

### Step 3: Add Redis (Production)

**Why Redis?**
- In-memory store (fast lookups)
- Shared across app servers
- Built-in expiration

**Setup:**

```ruby
# Gemfile
gem 'redis'
gem 'hiredis'

# config/initializers/redis.rb
Redis.current = Redis.new(
  url: ENV['REDIS_URL'] || 'redis://localhost:6379/1',
  driver: :hiredis
)

# config/initializers/rack_attack.rb
Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
  url: ENV['REDIS_URL'] || 'redis://localhost:6379/1'
)
```

**For development (no Redis):**
```ruby
# config/initializers/rack_attack.rb
if Rails.env.development?
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
end
```

---

### Step 4: Update Application Controller

```ruby
# frozen_string_literal: true

# app/controllers/application_controller.rb
class ApplicationController < ActionController::API
  # Handle rate limit errors
  rescue_from Rack::Attack::Throttle, with: :handle_throttle

  private

  def handle_throttle
    render json: {
      success: false,
      message: 'Too many requests. Please slow down.',
      error_code: 'RATE_LIMIT_EXCEEDED'
    }, status: :too_many_requests
  end
end
```

---

## Rate Limit Configuration

### Recommended Limits

```ruby
# config/initializers/rack_attack.rb

# General API (all endpoints)
throttle('req/ip', limit: 300, period: 5.minutes) do |req|
  req.ip
end
# → 300 requests per 5 minutes = 1 request/second average
# Burst allowed: 300 in first second, then rate limited

# Sync endpoint (per IP)
throttle('sync/ip', limit: 10, period: 1.second) do |req|
  req.ip if req.path == '/api/v1/data/sync' && req.post?
end
# → Max 10 concurrent batches per IP per second
# Allows concurrent batching (5-10 batches at once)

# Sync endpoint (per user)
throttle('sync/user', limit: 5, period: 1.second) do |req|
  if req.path == '/api/v1/data/sync' && req.post?
    extract_user_id(req)
  end
end
# → Max 5 concurrent batches per user per second
# Optimal for Phase 2.5 concurrent batching

# Login (prevent brute force)
throttle('login/email', limit: 5, period: 20.minutes) do |req|
  if req.path == '/api/v1/auth/login' && req.post?
    req.params['email'].to_s.downcase
  end
end
# → Max 5 login attempts per email per 20 minutes
```

---

## Testing Rate Limits

### Unit Tests

```ruby
# frozen_string_literal: true

# spec/requests/rate_limiting_spec.rb
require 'rails_helper'

RSpec.describe 'Rate Limiting' do
  let(:user) { create(:user) }
  let(:token) { generate_jwt_token(user) }

  before do
    # Clear Rack::Attack cache before each test
    Rack::Attack.cache.store.clear
  end

  describe 'sync endpoint rate limiting' do
    it 'allows 5 requests per second' do
      5.times do
        post '/api/v1/data/sync',
             params: { pageVisits: [build(:page_visit).attributes] },
             headers: { 'Authorization' => "Bearer #{token}" }

        expect(response).to have_http_status(:ok)
      end
    end

    it 'blocks 6th request in same second' do
      # Send 5 successful requests
      5.times do
        post '/api/v1/data/sync',
             params: { pageVisits: [build(:page_visit).attributes] },
             headers: { 'Authorization' => "Bearer #{token}" }
      end

      # 6th request should be rate limited
      post '/api/v1/data/sync',
           params: { pageVisits: [build(:page_visit).attributes] },
           headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['error_code']).to eq('RATE_LIMIT_EXCEEDED')
    end

    it 'includes rate limit headers' do
      post '/api/v1/data/sync',
           params: { pageVisits: [build(:page_visit).attributes] },
           headers: { 'Authorization' => "Bearer #{token}" }

      expect(response.headers['X-RateLimit-Limit']).to be_present
      expect(response.headers['X-RateLimit-Remaining']).to be_present
    end

    it 'resets after 1 second' do
      # Send 5 requests
      5.times do
        post '/api/v1/data/sync',
             params: { pageVisits: [build(:page_visit).attributes] },
             headers: { 'Authorization' => "Bearer #{token}" }
      end

      # Wait 1 second
      sleep 1.1

      # Should allow new request
      post '/api/v1/data/sync',
           params: { pageVisits: [build(:page_visit).attributes] },
           headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:ok)
    end
  end
end
```

---

### Manual Testing

```bash
# Test with curl

# Should succeed (first request)
curl -X POST http://localhost:3001/api/v1/data/sync \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"pageVisits":[...]}'

# Send 5 more quickly
for i in {1..5}; do
  curl -X POST http://localhost:3001/api/v1/data/sync \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"pageVisits":[...]}' &
done
wait

# 6th should return 429
curl -X POST http://localhost:3001/api/v1/data/sync \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"pageVisits":[...]}'

# Response:
# {
#   "success": false,
#   "message": "Rate limit exceeded. Please slow down.",
#   "retry_after": 1,
#   "error_code": "RATE_LIMIT_EXCEEDED"
# }
```

---

## Monitoring & Logging

### Add Logging

```ruby
# config/initializers/rack_attack.rb

# Log blocked requests
ActiveSupport::Notifications.subscribe('rack.attack') do |name, start, finish, request_id, payload|
  req = payload[:request]

  if req.env['rack.attack.matched']
    Rails.logger.warn(
      "[Rack::Attack] Throttled: #{req.env['rack.attack.matched']} " \
      "IP: #{req.ip} " \
      "Path: #{req.path} " \
      "User: #{extract_user_id(req)}"
    )
  end
end

def self.extract_user_id(req)
  token = req.env['HTTP_AUTHORIZATION']&.sub('Bearer ', '')
  decoded = decode_token(token)
  decoded['sub'] if decoded
rescue StandardError
  nil
end
```

### Monitor in Production

```bash
# Check Redis for rate limit data
redis-cli

> KEYS rack::attack:*
> GET "rack::attack:allow2ban:count:192.168.1.1"
> TTL "rack::attack:sync/user:123"
```

---

## Browser Extension Handling

### Detect 429 and Retry

```javascript
// extension/src/api/sync.js

async function syncBatch(batch, retries = 3) {
  try {
    const response = await api.post('/data/sync', { pageVisits: batch })
    return { success: true, data: response.data }
  } catch (error) {
    if (error.response?.status === 429) {
      // Rate limited!
      const retryAfter = error.response.data.retry_after || 1

      if (retries > 0) {
        console.log(`Rate limited, waiting ${retryAfter}s before retry...`)
        await sleep(retryAfter * 1000)
        return syncBatch(batch, retries - 1)  // Retry
      } else {
        return { success: false, error: 'RATE_LIMIT_EXCEEDED' }
      }
    }

    throw error  // Other errors
  }
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}
```

---

## Configuration Options

### Environment-Based Limits

```ruby
# config/initializers/rack_attack.rb

# Different limits for different environments
SYNC_RATE_LIMIT = if Rails.env.production?
                    5  # Production: strict limit
                  elsif Rails.env.staging?
                    10  # Staging: relaxed for testing
                  else
                    100  # Development: no real limit
                  end

throttle('sync/user', limit: SYNC_RATE_LIMIT, period: 1.second) do |req|
  # ...
end
```

### User-Specific Overrides

```ruby
# Premium users get higher limits
throttle('sync/user', limit: 1, period: 1.second) do |req|
  if req.path == '/api/v1/data/sync' && req.post?
    user_id = extract_user_id(req)
    user = User.find_by(id: user_id)

    # Premium users: allow 10 concurrent
    # Free users: allow 5 concurrent
    limit = user&.premium? ? 10 : 5

    # Return user_id and override limit
    [user_id, limit]
  end
end
```

---

## Summary

### What Rate Limiting Provides

1. **Protection** - Prevents server overload
2. **Fairness** - All users get equal access
3. **Stability** - Server stays responsive
4. **Security** - Prevents DOS attacks

### Limits

```
General API:    300 requests / 5 minutes
Sync (IP):      10 requests / second
Sync (User):    5 requests / second  ← Allows concurrent batching!
Login:          5 attempts / 20 minutes
```

### Next Steps

1. Add Rack::Attack gem
2. Configure rate limits
3. Add Redis (production)
4. Write tests
5. Test manually
6. Deploy
7. Monitor logs

---

**Status:** Ready for Implementation
**Dependencies:** Redis (production only)
**Next:** Implement concurrent batching in extension (02-extension-concurrent-sync.md)
