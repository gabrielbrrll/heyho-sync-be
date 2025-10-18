# Defense-in-Depth Security: Beyond Encryption

## TL;DR: Multiple Layers of Protection

**Core Principle:** Security is not just encryption - it's layers of protection at every level.

**The Question:** "Rather than encrypting, are there other ways we can ensure that the user's data is safe with us?"

**The Answer:** YES - encryption is just ONE layer. Here are 11 other critical security measures:

---

## The Security Layers (Defense in Depth)

```
┌────────────────────────────────────────┐
│ Layer 11: Legal & Compliance          │ ← Privacy Policy, GDPR, Audits
├────────────────────────────────────────┤
│ Layer 10: Incident Response           │ ← Breach procedures, monitoring
├────────────────────────────────────────┤
│ Layer 9: User Controls                │ ← Delete data, export, audit logs
├────────────────────────────────────────┤
│ Layer 8: Logging & Monitoring         │ ← Detect attacks, audit access
├────────────────────────────────────────┤
│ Layer 7: Rate Limiting & DDoS         │ ← Prevent abuse
├────────────────────────────────────────┤
│ Layer 6: Network Security             │ ← TLS, Firewall, VPC
├────────────────────────────────────────┤
│ Layer 5: Database Security            │ ← Row-level security, backups
├────────────────────────────────────────┤
│ Layer 4: Application Security         │ ← SQL injection, XSS prevention
├────────────────────────────────────────┤
│ Layer 3: Authentication & Authorization│ ← Who can access what
├────────────────────────────────────────┤
│ Layer 2: Infrastructure Security      │ ← Server hardening, containers
├────────────────────────────────────────┤
│ Layer 1: Data Minimization            │ ← Don't collect what you don't need
└────────────────────────────────────────┘
```

**Key Insight:** Even without encryption, these 11 layers provide strong protection.

---

## Layer 1: Data Minimization (Most Important!)

### Principle: Don't Collect What You Don't Need

**What We DON'T Need to Store:**
- ❌ User passwords (plaintext) → Hash with bcrypt
- ❌ Full URLs with sensitive params → Strip or hash query strings
- ❌ IP addresses long-term → Delete after 30 days
- ❌ User agent strings → Store only browser/OS category
- ❌ Session data beyond expiry → Auto-delete old sessions
- ❌ Deleted data → Hard delete, don't soft-delete forever

**What We MUST Store (Minimized):**
- ✅ Email (required for login, but can be hashed for lookups)
- ✅ Browsing data (core product feature)
- ✅ Timestamps (for analytics)
- ✅ Domains (for insights)

**Implementation:**

```ruby
# app/models/page_visit.rb
class PageVisit < ApplicationRecord
  # Strip sensitive query params before saving
  before_save :sanitize_url

  private

  def sanitize_url
    # Remove common sensitive params
    uri = URI.parse(url)
    if uri.query
      params = URI.decode_www_form(uri.query)
      # Remove sensitive params
      params.reject! { |k, _| k.match?(/token|key|secret|password|auth/i) }
      uri.query = URI.encode_www_form(params)
      self.url = uri.to_s
    end
  rescue URI::InvalidURIError
    # Invalid URL, keep as-is or reject
  end
end
```

```ruby
# config/initializers/data_retention.rb
# Auto-delete old data
class DataRetentionJob < ApplicationJob
  def perform
    # Delete old IP addresses
    User.where('last_sign_in_at < ?', 30.days.ago).update_all(last_sign_in_ip: nil)

    # Delete old sessions
    Session.where('created_at < ?', 90.days.ago).delete_all

    # Delete soft-deleted records after 30 days
    User.only_deleted.where('deleted_at < ?', 30.days.ago).each(&:really_destroy!)
  end
end
```

---

## Layer 2: Infrastructure Security

### Principle: Secure the Server Before Worrying About Data

**Server Hardening:**

1. **Disable root SSH login**
```bash
# /etc/ssh/sshd_config
PermitRootLogin no
PasswordAuthentication no  # Key-based only
```

2. **Firewall (UFW)**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp   # SSH
ufw allow 80/tcp   # HTTP
ufw allow 443/tcp  # HTTPS
ufw enable
```

3. **Automatic security updates**
```bash
# Ubuntu
apt install unattended-upgrades
dpkg-reconfigure --priority=low unattended-upgrades
```

4. **Fail2ban (Block brute-force attacks)**
```bash
apt install fail2ban
systemctl enable fail2ban
```

**Container Security (Docker):**

```dockerfile
# Use non-root user in Docker
FROM ruby:3.2-alpine

# Create app user
RUN addgroup -g 1000 app && \
    adduser -D -u 1000 -G app app

# Run as app user (not root!)
USER app

# Read-only filesystem where possible
VOLUME ["/app/tmp", "/app/log"]
```

**Environment Variables:**
```bash
# Never commit secrets to git
# Use environment variables or secret management

# .env (gitignored)
DATABASE_URL=postgresql://...
SECRET_KEY_BASE=...
JWT_SECRET=...
```

---

## Layer 3: Authentication & Authorization

### Principle: Control Who Can Access What

**Strong Password Policies:**

```ruby
# app/models/user.rb
class User < ApplicationRecord
  validates :password, length: { minimum: 12 }, if: :password_required?
  validates :password, format: {
    with: /\A(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/,
    message: "must include uppercase, lowercase, and number"
  }, if: :password_required?

  # Use bcrypt (cost factor 12+)
  has_secure_password validations: false
end
```

**Multi-Factor Authentication (MFA):**

```ruby
# Add TOTP-based 2FA
gem 'rotp'  # Time-based OTP

class User < ApplicationRecord
  has_encrypted :otp_secret

  def enable_2fa!
    self.otp_secret = ROTP::Base32.random
    save!
  end

  def verify_2fa(code)
    totp = ROTP::TOTP.new(otp_secret)
    totp.verify(code, drift_behind: 15, drift_ahead: 15)
  end
end
```

**Role-Based Access Control (RBAC):**

```ruby
# app/models/user.rb
class User < ApplicationRecord
  enum role: { user: 0, admin: 1, super_admin: 2 }

  def can_access?(resource)
    # Users can only access their own data
    return true if resource.user_id == id
    # Admins can access some resources
    return true if admin? && resource.is_a?(Report)
    # Super admins can access everything
    return true if super_admin?

    false
  end
end
```

**Token Security:**

```ruby
# app/services/authentication/token_service.rb
class Authentication::TokenService
  # Short-lived access tokens (1 hour)
  ACCESS_TOKEN_EXPIRY = 1.hour

  # Longer-lived refresh tokens (7 days)
  REFRESH_TOKEN_EXPIRY = 7.days

  def self.generate_jwt_token(user)
    JWT.encode(
      {
        sub: user.id,
        jti: SecureRandom.uuid,  # Unique token ID
        iss: 'heyho-sync-api',
        aud: 'heyho-sync-app',
        iat: Time.now.to_i,
        exp: ACCESS_TOKEN_EXPIRY.from_now.to_i,
        scope: 'user'
      },
      jwt_secret,
      'HS256'
    )
  end

  # Token revocation list
  def self.revoke_token(jti)
    Redis.current.setex("revoked:#{jti}", ACCESS_TOKEN_EXPIRY, '1')
  end

  def self.revoked?(jti)
    Redis.current.exists?("revoked:#{jti}")
  end
end
```

---

## Layer 4: Application Security

### Principle: Prevent Common Web Attacks

**1. SQL Injection Prevention:**

```ruby
# BAD - SQL injection vulnerable
User.where("email = '#{params[:email]}'")

# GOOD - Use parameterized queries
User.where(email: params[:email])

# GOOD - Use placeholders
User.where("email = ? AND active = ?", params[:email], true)
```

**2. XSS (Cross-Site Scripting) Prevention:**

```ruby
# Rails auto-escapes HTML in views
<%= user.name %>  # Safe (escaped)
<%== user.name %> # UNSAFE (raw HTML)

# Sanitize user input
class PageVisit < ApplicationRecord
  before_save :sanitize_title

  private

  def sanitize_title
    self.title = ActionController::Base.helpers.sanitize(title)
  end
end
```

**3. CSRF (Cross-Site Request Forgery) Prevention:**

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::API
  # For API, use token-based auth (not cookies)
  # CSRF protection not needed for stateless APIs

  # For session-based apps:
  # protect_from_forgery with: :exception
end
```

**4. Mass Assignment Protection:**

```ruby
# app/controllers/users_controller.rb
def user_params
  # Only allow specific fields
  params.require(:user).permit(:email, :first_name, :last_name)
  # Never permit :role, :admin, etc. from user input
end
```

**5. Secure Headers:**

```ruby
# config/initializers/secure_headers.rb
SecureHeaders::Configuration.default do |config|
  config.x_frame_options = "DENY"
  config.x_content_type_options = "nosniff"
  config.x_xss_protection = "1; mode=block"
  config.x_download_options = "noopen"
  config.x_permitted_cross_domain_policies = "none"
  config.referrer_policy = "strict-origin-when-cross-origin"

  # Content Security Policy
  config.csp = {
    default_src: %w['self'],
    script_src: %w['self'],
    style_src: %w['self' 'unsafe-inline'],
    img_src: %w['self' data: https:],
    font_src: %w['self' data:],
    connect_src: %w['self'],
    frame_ancestors: %w['none']
  }
end
```

---

## Layer 5: Database Security

### Principle: Secure Data at the Database Level

**1. Row-Level Security (PostgreSQL):**

```sql
-- Enable RLS on table
ALTER TABLE page_visits ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only see their own data
CREATE POLICY user_isolation_policy ON page_visits
  FOR ALL
  TO app_user
  USING (user_id = current_setting('app.current_user_id')::integer);

-- Set user context in Rails
# app/controllers/application_controller.rb
before_action :set_database_user_context

def set_database_user_context
  if current_user
    ActiveRecord::Base.connection.execute(
      "SET LOCAL app.current_user_id = #{current_user.id}"
    )
  end
end
```

**2. Database Access Control:**

```sql
-- Create limited database user for app
CREATE USER app_user WITH PASSWORD 'strong_password';

-- Grant only necessary permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON page_visits TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO app_user;

-- Revoke dangerous permissions
REVOKE ALL ON schema_migrations FROM app_user;
REVOKE DROP ON DATABASE sync_be_production FROM app_user;
```

**3. Database Connection Security:**

```yaml
# config/database.yml
production:
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>

  # Use SSL for database connections
  sslmode: require

  # Use connection pooling with timeout
  checkout_timeout: 5

  # Separate read-only replica for analytics
  replica:
    <<: *default
    username: readonly_user
    replica: true
```

**4. Automated Backups:**

```bash
#!/bin/bash
# backup_database.sh

# Backup to encrypted storage
pg_dump $DATABASE_URL | \
  gzip | \
  gpg --encrypt --recipient backup@heyho.com | \
  aws s3 cp - s3://heyho-backups/$(date +%Y%m%d-%H%M%S).sql.gz.gpg

# Retention: Keep 7 daily, 4 weekly, 12 monthly
```

**5. Database Audit Logging:**

```sql
-- PostgreSQL pgAudit extension
CREATE EXTENSION pgaudit;

-- Log all data modifications
ALTER SYSTEM SET pgaudit.log = 'write';
ALTER SYSTEM SET pgaudit.log_relation = on;
```

---

## Layer 6: Network Security

### Principle: Secure Data in Transit

**1. TLS/SSL Everywhere:**

```nginx
# nginx.conf
server {
  listen 443 ssl http2;
  server_name api.heyho.com;

  # Modern TLS config
  ssl_certificate /etc/letsencrypt/live/api.heyho.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/api.heyho.com/privkey.pem;

  ssl_protocols TLSv1.3 TLSv1.2;
  ssl_ciphers HIGH:!aNULL:!MD5;
  ssl_prefer_server_ciphers on;

  # HSTS (force HTTPS)
  add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

  # Redirect HTTP to HTTPS
  if ($scheme != "https") {
    return 301 https://$server_name$request_uri;
  }
}
```

**2. Private Network (VPC):**

```yaml
# docker-compose.yml (production)
services:
  db:
    image: postgres:15
    networks:
      - private  # Database not exposed to internet
    ports: []    # No external ports

  api:
    image: sync-api:latest
    networks:
      - private
      - public
    ports:
      - "3000:3000"  # Only API exposed

networks:
  private:
    internal: true  # No internet access
  public:
    external: true
```

**3. API Gateway / Reverse Proxy:**

```nginx
# Rate limiting
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;

server {
  location /api/ {
    limit_req zone=api burst=20 nodelay;

    # Hide internal headers
    proxy_hide_header X-Powered-By;
    proxy_hide_header Server;

    proxy_pass http://backend:3000;
  }
}
```

---

## Layer 7: Rate Limiting & DDoS Protection

### Principle: Prevent Abuse and Overload

**1. Application-Level Rate Limiting:**

```ruby
# config/initializers/rack_attack.rb
class Rack::Attack
  # Throttle all requests by IP
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  # Throttle login attempts
  throttle('login/email', limit: 5, period: 20.minutes) do |req|
    if req.path == '/api/v1/auth/login' && req.post?
      req.params['email'].to_s.downcase.presence
    end
  end

  # Throttle API requests by user
  throttle('api/user', limit: 1000, period: 1.hour) do |req|
    req.env['current_user']&.id if req.path.start_with?('/api/')
  end

  # Block IPs from banned list
  blocklist('block bad IPs') do |req|
    Redis.current.sismember('banned_ips', req.ip)
  end

  # Custom response for throttled requests
  self.throttled_responder = lambda do |env|
    [
      429,
      { 'Content-Type' => 'application/json' },
      [{ error: 'Rate limit exceeded. Try again later.' }.to_json]
    ]
  end
end
```

**2. CDN & DDoS Protection:**

```yaml
# Use Cloudflare or similar
# - Absorbs DDoS attacks
# - Rate limiting at edge
# - Bot detection
# - Geographic filtering
```

---

## Layer 8: Logging & Monitoring

### Principle: Detect Attacks Early

**1. Centralized Logging:**

```ruby
# config/environments/production.rb
config.log_level = :info
config.log_tags = [:request_id, :remote_ip]

# Use structured logging
config.logger = ActiveSupport::Logger.new(STDOUT)
config.log_formatter = ::Logger::Formatter.new

# Log to external service (e.g., Papertrail, Datadog)
config.logger = RemoteLogger.new(ENV['LOG_URL'])
```

**2. Security Event Logging:**

```ruby
# app/services/security_logger.rb
class SecurityLogger
  EVENTS = %i[
    login_success
    login_failure
    password_reset_request
    password_changed
    account_deleted
    suspicious_activity
    rate_limit_exceeded
  ]

  def self.log(event, user: nil, metadata: {})
    Rails.logger.info(
      event: event,
      user_id: user&.id,
      user_email: user&.email,
      ip: metadata[:ip],
      user_agent: metadata[:user_agent],
      timestamp: Time.current,
      **metadata
    )

    # Also store in database for audit trail
    SecurityEvent.create!(
      event_type: event,
      user: user,
      metadata: metadata,
      ip_address: metadata[:ip]
    )
  end
end

# Usage
SecurityLogger.log(:login_failure, user: user, metadata: { ip: request.ip })
```

**3. Real-Time Monitoring:**

```ruby
# config/initializers/exception_notification.rb
# Get notified of errors immediately
Rails.application.config.middleware.use(
  ExceptionNotification::Rack,
  email: {
    email_prefix: "[HEYHO ERROR] ",
    sender_address: %("Heyho API" <errors@heyho.com>),
    exception_recipients: %w[dev@heyho.com]
  },
  slack: {
    webhook_url: ENV['SLACK_WEBHOOK_URL'],
    channel: '#alerts'
  }
)
```

**4. Intrusion Detection:**

```ruby
# app/services/intrusion_detector.rb
class IntrusionDetector
  SUSPICIOUS_PATTERNS = [
    /union.*select/i,     # SQL injection
    /<script>/i,          # XSS
    /\.\.\/\.\.\//,       # Path traversal
    /eval\(/i,            # Code injection
  ].freeze

  def self.check_request(params)
    params.each do |key, value|
      next unless value.is_a?(String)

      SUSPICIOUS_PATTERNS.each do |pattern|
        if value.match?(pattern)
          SecurityLogger.log(
            :suspicious_activity,
            metadata: {
              pattern: pattern,
              param: key,
              value: value
            }
          )
          raise SecurityError, "Suspicious input detected"
        end
      end
    end
  end
end
```

---

## Layer 9: User Controls & Transparency

### Principle: Give Users Control Over Their Data

**1. Export Data (GDPR Right to Portability):**

```ruby
# app/services/data_exporter.rb
class DataExporter
  def self.export(user)
    {
      user: user.as_json(only: [:email, :created_at]),
      page_visits: user.page_visits.as_json,
      tab_aggregates: user.tab_aggregates.as_json,
      reading_list: user.reading_list_items.as_json,
      exported_at: Time.current
    }.to_json
  end
end

# API endpoint
# GET /api/v1/users/export
def export
  data = DataExporter.export(current_user)
  send_data data, filename: "heyho-data-#{Date.current}.json"
end
```

**2. Delete All Data (GDPR Right to Erasure):**

```ruby
# app/models/user.rb
class User < ApplicationRecord
  def anonymize_and_delete!
    transaction do
      # Delete all related data
      page_visits.delete_all
      tab_aggregates.delete_all
      reading_list_items.delete_all
      research_sessions.delete_all

      # Anonymize user record
      update!(
        email: "deleted-#{id}@deleted.heyho.com",
        password: SecureRandom.hex(32),
        deleted_at: Time.current
      )

      # Log deletion
      SecurityLogger.log(:account_deleted, user: self)
    end
  end
end
```

**3. Access Log (Show User Who Accessed Their Data):**

```ruby
# app/models/access_log.rb
class AccessLog < ApplicationRecord
  belongs_to :user

  scope :recent, -> { order(created_at: :desc).limit(100) }
end

# API endpoint
# GET /api/v1/users/access_logs
def access_logs
  logs = current_user.access_logs.recent
  render json: logs
end
```

**4. Privacy Dashboard:**

```
┌─────────────────────────────────────────────────┐
│ 🔒 Your Privacy & Security                      │
├─────────────────────────────────────────────────┤
│ Data We Have:                                   │
│ • 1,234 page visits (last 90 days)              │
│ • 56 reading list items                         │
│ • 12 research sessions                          │
│                                                  │
│ Recent Access:                                  │
│ • Oct 16, 2:30pm - API sync (your extension)    │
│ • Oct 16, 9:15am - Dashboard view (you)         │
│ • Oct 15, 5:00pm - API sync (your extension)    │
│                                                  │
│ Actions:                                        │
│ [Export My Data]  [Delete My Account]           │
│ [View Full Access Log]                          │
└─────────────────────────────────────────────────┘
```

---

## Layer 10: Incident Response

### Principle: Be Prepared for Breaches

**1. Incident Response Plan:**

```markdown
# SECURITY INCIDENT RESPONSE PLAN

## Phase 1: Detection (0-15 minutes)
- Monitor alerts (intrusion detection, unusual access)
- Identify scope (what data, how many users)
- Preserve evidence (logs, database snapshots)

## Phase 2: Containment (15-60 minutes)
- Isolate affected systems
- Revoke compromised credentials
- Block attacker IPs
- Enable maintenance mode if needed

## Phase 3: Eradication (1-4 hours)
- Remove attacker access
- Patch vulnerabilities
- Reset secrets/keys
- Verify no backdoors

## Phase 4: Recovery (4-24 hours)
- Restore from clean backups if needed
- Bring systems back online
- Monitor for re-infection

## Phase 5: Notification (24-72 hours)
- Notify affected users (GDPR requires 72 hours)
- Publish incident report
- Contact authorities if required

## Phase 6: Post-Mortem (1-2 weeks)
- Document what happened
- Identify root causes
- Implement preventive measures
- Update response plan
```

**2. Automated Incident Detection:**

```ruby
# app/services/incident_detector.rb
class IncidentDetector
  # Run every 5 minutes
  def self.check
    check_failed_logins
    check_unusual_data_access
    check_database_anomalies
  end

  def self.check_failed_logins
    recent_failures = SecurityEvent
      .where(event_type: 'login_failure')
      .where('created_at > ?', 5.minutes.ago)
      .count

    if recent_failures > 100
      alert("High number of failed logins: #{recent_failures}")
    end
  end

  def self.check_unusual_data_access
    # Detect if someone is accessing too much data
    User.find_each do |user|
      recent_requests = user.access_logs.where('created_at > ?', 1.hour.ago).count

      if recent_requests > 1000
        alert("User #{user.id} making excessive requests: #{recent_requests}")
      end
    end
  end

  def self.alert(message)
    # Send to Slack, email, PagerDuty, etc.
    Rails.logger.error("[SECURITY ALERT] #{message}")
    # SlackNotifier.notify(message)
    # PagerDuty.trigger(message)
  end
end
```

---

## Layer 11: Legal & Compliance

### Principle: Be Transparent and Compliant

**1. Privacy Policy (Required!):**

```markdown
# HEYHO PRIVACY POLICY

## What We Collect
- Email address (for login)
- Browsing data (URLs, page titles, timestamps)
- Usage analytics (features used)

## Why We Collect It
- To provide insights into your browsing habits
- To detect patterns (hoarder tabs, serial openers)
- To improve our service

## What We DON'T Do
- ❌ Sell your data
- ❌ Share with advertisers
- ❌ Track you across other sites
- ❌ Use for purposes beyond our service

## Your Rights (GDPR/CCPA)
- ✅ Access your data (export anytime)
- ✅ Delete your data (account deletion)
- ✅ Correct your data (edit profile)
- ✅ Opt-out of analytics (coming soon)

## Data Retention
- Browsing data: 90 days (free), unlimited (pro)
- Deleted accounts: Anonymized within 30 days
- Backups: Encrypted, deleted after 90 days

## Security Measures
- TLS encryption for data in transit
- Secure servers with firewalls
- Regular security audits
- Limited employee access
```

**2. Terms of Service:**

```markdown
# TERMS OF SERVICE

## Prohibited Uses
You may NOT use Heyho to:
- Violate laws
- Infringe copyrights
- Share accounts
- Reverse engineer our service
- Abuse rate limits

## Data Ownership
- You own your data
- We have license to process it for our service
- You can export/delete anytime

## Service Availability
- We aim for 99.9% uptime
- No guarantee of zero downtime
- Scheduled maintenance announced 24h ahead
```

**3. Security Audits:**

```yaml
# Schedule regular audits
- Code security audit: Quarterly
- Penetration testing: Annually
- Dependency updates: Weekly (automated)
- Security training: Bi-annually
```

---

## Summary: Defense in Depth

### Even Without Encryption, You Can Be Secure

**The 11 Layers:**

1. ✅ **Data Minimization** - Don't collect sensitive query params
2. ✅ **Infrastructure Security** - Firewall, SSH keys, auto-updates
3. ✅ **Authentication** - Strong passwords, 2FA, token security
4. ✅ **Application Security** - SQL injection, XSS prevention
5. ✅ **Database Security** - Row-level security, backups, SSL
6. ✅ **Network Security** - TLS everywhere, private networks
7. ✅ **Rate Limiting** - Prevent abuse, DDoS protection
8. ✅ **Logging & Monitoring** - Detect attacks, audit access
9. ✅ **User Controls** - Export, delete, access logs
10. ✅ **Incident Response** - Be prepared for breaches
11. ✅ **Legal & Compliance** - Privacy policy, GDPR, audits

**With These Layers:**
- User data is protected even without encryption
- Attacks are detected early
- Breaches are contained quickly
- Users have control and transparency

**Encryption is STILL Recommended:**
- It's an additional layer (Layer 12)
- But it's not a replacement for the above
- Security is about layers, not a single solution

---

## Recommendation: Hybrid Approach

**Phase 2 Implementation:**

### Week 1-2: Core Security (No Encryption)
1. Data minimization (sanitize URLs)
2. Strong authentication (2FA optional)
3. Rate limiting
4. Secure headers
5. Database row-level security

### Week 3-4: Monitoring & User Controls
6. Logging & monitoring
7. User export/delete
8. Access logs
9. Privacy dashboard

### Week 5-6: Optional Encryption Layer
10. Add field-level encryption for extra security
11. But only after other layers are solid

**Result:**
- Secure from day 1 (even before encryption)
- Users trust you (transparency + controls)
- Compliant with GDPR/CCPA
- Encryption is a bonus, not a requirement

---

**Status:** Alternative Security Architecture
**Last Updated:** 2025-10-18
**Key Insight:** Encryption is one tool in a toolbox. Defense in depth provides strong security even without it.
