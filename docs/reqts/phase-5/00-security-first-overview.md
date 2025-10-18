# Phase 2: Security-First Architecture - Zero Knowledge Privacy

## Mission Statement

**"We cannot see your browsing history. Ever."**

Phase 2 is a complete security overhaul to ensure:
1. **End-to-end encryption** - Your data is encrypted before it leaves your device
2. **Zero-knowledge architecture** - We cannot decrypt your data, even if we wanted to
3. **Client-side keys** - You control the encryption keys, not us
4. **Minimal data collection** - We only store what you explicitly choose to sync
5. **Transparent & auditable** - Open source crypto, third-party audits

---

## The Problem

### Current State (Phase 1)
```
Browser Extension → Plaintext JSON → Server → Database (plaintext)
                                        ↓
                                   We can read
                                   everything
```

**What we can currently see:**
- Every URL you visited
- Every page title
- How long you spent on each site
- Your entire browsing history
- Timestamps of all activity

**This is unacceptable for privacy-conscious users.**

---

## The Solution: Zero-Knowledge Architecture

### New Architecture
```
Browser Extension
    ↓ (1. Generate user encryption key)
    ↓ (2. Encrypt data with user's key)
    ↓
Encrypted JSON → Server → Database (encrypted blobs)
    ↓                        ↓
    ✅ User can decrypt    ❌ We CANNOT decrypt
```

**What we can see after Phase 2:**
- User ID (for account management)
- Data size (for storage quotas)
- Sync timestamps (for conflict resolution)
- **Nothing else. All browsing data is encrypted.**

---

## Core Security Principles

### 1. Client-Side Encryption Only

**Rule:** All sensitive data MUST be encrypted on the client before transmission.

**Implementation:**
```javascript
// Browser Extension
import { encrypt, decrypt } from './crypto';

// User's master key (derived from password or device-specific)
const userMasterKey = deriveKeyFromPassword(userPassword);

// Encrypt before sending to server
const encryptedData = {
  page_visits: encrypt(pageVisits, userMasterKey),
  tab_aggregates: encrypt(tabAggregates, userMasterKey),
  metadata: {
    version: 1,
    algorithm: 'AES-256-GCM',
    timestamp: Date.now()
  }
};

// Server receives encrypted blob - cannot read contents
await api.sync(encryptedData);
```

**Server NEVER sees:**
- URLs
- Page titles
- Domains
- Any browsing data in plaintext

---

### 2. Zero-Knowledge Proof of Storage

**Concept:** Prove we stored your data without knowing what it is.

**How it works:**
```
Client: "Here's encrypted data + checksum"
Server: "Stored. Here's proof of storage (hash + timestamp + signature)"
Client: "Verified. I can trust data is intact."
```

**Implementation:**
```javascript
// Client sends
{
  encrypted_blob: "8f3a9c2b...", // AES-256 encrypted
  checksum: "sha256-abc123",     // Client-computed hash
  user_id: 123
}

// Server stores and returns
{
  storage_proof: {
    blob_hash: "sha256-abc123",   // Matches client checksum
    stored_at: "2025-10-16T...",
    server_signature: "RSA-sig...", // Server signs the hash
    retrieval_token: "token-xyz"
  }
}

// Client verifies server actually stored it
const verified = verifyServerSignature(
  storage_proof.blob_hash,
  storage_proof.server_signature,
  serverPublicKey
);
```

---

### 3. Key Management (Client-Side Only)

**Critical:** Encryption keys NEVER leave the user's device.

**Key Derivation Strategy:**

**Option A: Password-Based Key Derivation (PBKDF2)**
```javascript
// Derive encryption key from user's password
const masterKey = await crypto.subtle.deriveKey(
  {
    name: 'PBKDF2',
    salt: userSalt, // Stored locally, never sent to server
    iterations: 600000, // High iteration count
    hash: 'SHA-256'
  },
  passwordKey,
  { name: 'AES-GCM', length: 256 },
  false, // Not extractable
  ['encrypt', 'decrypt']
);
```

**Option B: Device-Specific Key (Recommended for extensions)**
```javascript
// Generate device-specific key on first install
const deviceKey = await crypto.subtle.generateKey(
  { name: 'AES-GCM', length: 256 },
  true, // Extractable for backup
  ['encrypt', 'decrypt']
);

// Store in browser's secure storage
await chrome.storage.local.set({
  encrypted_master_key: await encryptKeyWithPassword(deviceKey, userPassword)
});
```

**Backup & Recovery:**
```javascript
// Export encrypted key for user backup
const backupKey = await exportEncryptedKey(masterKey, userPassword);
// User saves: "HEYHO-BACKUP-8f3a9c2b7d4e..."

// Recovery on new device
const restoredKey = await importEncryptedKey(backupKey, userPassword);
```

**Server NEVER receives or stores encryption keys.**

---

### 4. Secure Sync Protocol

**Sync Flow:**
```
1. Client generates session key (ephemeral, for this sync only)
2. Client encrypts data with master key
3. Client encrypts session metadata with session key
4. Server stores encrypted blobs
5. Server returns sync confirmation
6. Client verifies integrity
```

**API Request:**
```javascript
POST /api/v1/secure-sync
Authorization: Bearer <jwt-token>

{
  "encrypted_payload": {
    "data": "AES-GCM encrypted blob...",
    "nonce": "unique-nonce-123",
    "tag": "auth-tag-for-verification"
  },
  "metadata": {
    "version": 1,
    "algorithm": "AES-256-GCM",
    "client_timestamp": 1697472000,
    "checksum": "sha256-of-plaintext-data"
  }
}
```

**API Response:**
```json
{
  "success": true,
  "sync_id": "sync_abc123",
  "stored_at": "2025-10-16T15:30:00Z",
  "storage_proof": {
    "checksum_match": true,
    "server_signature": "RSA-signature...",
    "retrieval_token": "token-xyz"
  }
}
```

**Server CANNOT decrypt the payload.**

---

### 5. Privacy-Preserving Analytics (Optional)

**Challenge:** How do we provide insights without seeing user data?

**Solution A: Homomorphic Encryption (Advanced)**
- Perform computations on encrypted data
- Get encrypted results
- Client decrypts to see insights
- Too complex for MVP

**Solution B: Client-Side Analytics (Recommended)**
```javascript
// ALL analytics computed locally in browser extension
const insights = {
  total_sites_visited: pageVisits.length,
  total_time_seconds: sum(pageVisits.map(v => v.duration)),
  top_domains: computeTopDomains(pageVisits), // Done locally
  productivity_hours: analyzeEngagement(pageVisits) // Done locally
};

// Only send aggregated, anonymized metrics (if user opts in)
const anonymizedMetrics = {
  avg_engagement_rate: 0.67, // No domains, no URLs
  browsing_hours_per_day: 4.2,
  most_active_hour: 14 // 2pm, no specific sites
};

// Server receives anonymous stats only
await api.submitAnonymousMetrics(anonymizedMetrics);
```

**Solution C: Differential Privacy**
- Add mathematical noise to metrics
- Protects individual data points
- Allows aggregate trends
- See: https://en.wikipedia.org/wiki/Differential_privacy

---

## Database Schema Changes

### Old (Insecure) Schema
```sql
-- DON'T DO THIS
CREATE TABLE page_visits (
  id VARCHAR PRIMARY KEY,
  user_id INTEGER,
  url TEXT, -- ❌ PLAINTEXT
  title TEXT, -- ❌ PLAINTEXT
  domain VARCHAR, -- ❌ PLAINTEXT
  ...
);
```

### New (Secure) Schema
```sql
-- Encrypted storage
CREATE TABLE encrypted_browsing_data (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),

  -- Encrypted blob (AES-256-GCM)
  encrypted_payload BYTEA NOT NULL,

  -- Encryption metadata (NOT the key!)
  encryption_version INTEGER NOT NULL DEFAULT 1,
  algorithm VARCHAR(50) NOT NULL DEFAULT 'AES-256-GCM',
  nonce BYTEA NOT NULL, -- Unique per encryption
  auth_tag BYTEA NOT NULL, -- For verification

  -- Client-provided checksum (for integrity)
  client_checksum VARCHAR(64) NOT NULL,

  -- Server metadata (minimal)
  data_type VARCHAR(50) NOT NULL, -- 'page_visits', 'tab_aggregates'
  data_size_bytes INTEGER,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  -- Sync tracking
  sync_id VARCHAR(255) UNIQUE,
  client_id VARCHAR(255),
  device_fingerprint VARCHAR(255)
);

CREATE INDEX idx_encrypted_data_user ON encrypted_browsing_data(user_id);
CREATE INDEX idx_encrypted_data_sync ON encrypted_browsing_data(sync_id);
CREATE INDEX idx_encrypted_data_created ON encrypted_browsing_data(created_at);

-- NO indexes on URL, title, domain - because we can't see them!
```

**What the server can see:**
- ✅ User ID (to know whose data it is)
- ✅ Data size (for storage management)
- ✅ Sync timestamps (for conflict resolution)
- ✅ Encrypted blob (useless without decryption key)
- ❌ URLs, titles, domains, browsing behavior

---

## Encryption Implementation

### Client-Side (Browser Extension)

**File:** `apps/browser-extension/src/crypto/encryption.js`

```javascript
/**
 * AES-256-GCM Encryption
 * Industry standard, authenticated encryption
 */

export async function encryptData(plaintext, masterKey) {
  // Convert to bytes
  const encoder = new TextEncoder();
  const data = encoder.encode(JSON.stringify(plaintext));

  // Generate unique nonce (NEVER reuse!)
  const nonce = crypto.getRandomValues(new Uint8Array(12));

  // Encrypt with AES-GCM
  const encryptedBuffer = await crypto.subtle.encrypt(
    {
      name: 'AES-GCM',
      iv: nonce,
      tagLength: 128 // Authentication tag
    },
    masterKey,
    data
  );

  // Split encrypted data and auth tag
  const encrypted = new Uint8Array(encryptedBuffer);
  const authTag = encrypted.slice(-16); // Last 16 bytes
  const ciphertext = encrypted.slice(0, -16);

  return {
    encrypted: arrayBufferToBase64(ciphertext),
    nonce: arrayBufferToBase64(nonce),
    authTag: arrayBufferToBase64(authTag),
    algorithm: 'AES-256-GCM',
    version: 1
  };
}

export async function decryptData(encryptedData, masterKey) {
  // Convert from base64
  const ciphertext = base64ToArrayBuffer(encryptedData.encrypted);
  const nonce = base64ToArrayBuffer(encryptedData.nonce);
  const authTag = base64ToArrayBuffer(encryptedData.authTag);

  // Combine ciphertext + auth tag
  const combined = new Uint8Array(ciphertext.length + authTag.length);
  combined.set(new Uint8Array(ciphertext), 0);
  combined.set(new Uint8Array(authTag), ciphertext.length);

  // Decrypt
  const decryptedBuffer = await crypto.subtle.decrypt(
    {
      name: 'AES-GCM',
      iv: nonce,
      tagLength: 128
    },
    masterKey,
    combined
  );

  // Convert back to object
  const decoder = new TextDecoder();
  const plaintext = decoder.decode(decryptedBuffer);
  return JSON.parse(plaintext);
}

// Checksum for integrity verification
export async function computeChecksum(data) {
  const encoder = new TextEncoder();
  const dataBuffer = encoder.encode(JSON.stringify(data));
  const hashBuffer = await crypto.subtle.digest('SHA-256', dataBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return 'sha256-' + hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}
```

---

### Server-Side (Rails API)

**File:** `app/controllers/api/v1/secure_sync_controller.rb`

```ruby
# frozen_string_literal: true

module Api
  module V1
    class SecureSyncController < AuthenticatedController
      # POST /api/v1/secure-sync
      def sync
        # Validate request
        unless valid_encrypted_payload?
          return render_error_response(
            message: 'Invalid encrypted payload',
            status: :bad_request
          )
        end

        # Store encrypted blob (we CANNOT decrypt it)
        encrypted_record = current_user.encrypted_browsing_data.create!(
          encrypted_payload: decode_base64(params[:encrypted_payload][:data]),
          nonce: decode_base64(params[:encrypted_payload][:nonce]),
          auth_tag: decode_base64(params[:encrypted_payload][:tag]),
          encryption_version: params[:metadata][:version],
          algorithm: params[:metadata][:algorithm],
          client_checksum: params[:metadata][:checksum],
          data_type: params[:metadata][:data_type] || 'browsing_data',
          data_size_bytes: params[:encrypted_payload][:data].bytesize,
          sync_id: SecureRandom.uuid,
          client_id: params[:client_id]
        )

        # Generate proof of storage (sign the checksum)
        storage_proof = generate_storage_proof(encrypted_record)

        render_json_response(
          success: true,
          data: {
            sync_id: encrypted_record.sync_id,
            stored_at: encrypted_record.created_at,
            storage_proof: storage_proof
          },
          status: :created
        )
      end

      # GET /api/v1/secure-sync/:sync_id
      def retrieve
        encrypted_record = current_user.encrypted_browsing_data.find_by!(sync_id: params[:id])

        # Return encrypted blob (client will decrypt)
        render_json_response(
          success: true,
          data: {
            encrypted_payload: {
              data: encode_base64(encrypted_record.encrypted_payload),
              nonce: encode_base64(encrypted_record.nonce),
              tag: encode_base64(encrypted_record.auth_tag)
            },
            metadata: {
              version: encrypted_record.encryption_version,
              algorithm: encrypted_record.algorithm,
              checksum: encrypted_record.client_checksum,
              stored_at: encrypted_record.created_at
            }
          }
        )
      end

      private

      def valid_encrypted_payload?
        params[:encrypted_payload].present? &&
          params[:encrypted_payload][:data].present? &&
          params[:encrypted_payload][:nonce].present? &&
          params[:encrypted_payload][:tag].present? &&
          params[:metadata].present? &&
          params[:metadata][:checksum].present?
      end

      def generate_storage_proof(record)
        # Server signs the client's checksum
        # This proves we stored the data without knowing what it is
        data_to_sign = "#{record.client_checksum}:#{record.sync_id}:#{record.created_at.to_i}"
        signature = sign_with_server_key(data_to_sign)

        {
          checksum: record.client_checksum,
          sync_id: record.sync_id,
          stored_at: record.created_at,
          server_signature: signature,
          retrieval_token: generate_retrieval_token(record)
        }
      end

      def sign_with_server_key(data)
        # Use server's private key to sign
        private_key = OpenSSL::PKey::RSA.new(File.read(Rails.root.join('config', 'server_private_key.pem')))
        signature = private_key.sign(OpenSSL::Digest::SHA256.new, data)
        Base64.strict_encode64(signature)
      end

      def generate_retrieval_token(record)
        # Temporary token for retrieving this specific record
        payload = {
          sync_id: record.sync_id,
          user_id: record.user_id,
          exp: 24.hours.from_now.to_i
        }
        JWT.encode(payload, Rails.application.secret_key_base, 'HS256')
      end

      def decode_base64(data)
        Base64.strict_decode64(data)
      end

      def encode_base64(data)
        Base64.strict_encode64(data)
      end
    end
  end
end
```

**Key point:** Server NEVER attempts to decrypt. It only stores and retrieves encrypted blobs.

---

## Security Guarantees

### What We CAN Do
✅ Store your encrypted data securely
✅ Sync data across your devices
✅ Prove we stored your data correctly
✅ Delete your data on request
✅ Provide account management

### What We CANNOT Do
❌ Read your browsing history
❌ See URLs you visited
❌ Know what sites you use
❌ Decrypt your data (even if we wanted to)
❌ Share your data with anyone (it's encrypted)

### Technical Proof
```
Server receives: "8f3a9c2b7d4e1a5c9b..."
Server has: No decryption key
Server can: Only store the blob
Result: Server CANNOT read the data

Even if:
  - Database is breached
  - Server is hacked
  - Employee goes rogue
  - Government requests data
Your browsing history remains encrypted and unreadable.
```

---

## Audit & Transparency

### Open Source Cryptography
- All encryption code will be open source
- Use standard, audited libraries (Web Crypto API)
- No proprietary or custom crypto
- Community can verify our implementation

### Third-Party Security Audit
- Engage security firm to audit crypto implementation
- Publish audit results publicly
- Fix any findings before launch
- Annual re-audits

### Transparency Reports
- Publish quarterly reports:
  - Number of encryption keys we have access to: **0**
  - Number of times we decrypted user data: **0**
  - Number of government data requests: **X**
  - Number of requests we could fulfill: **0** (data is encrypted)

---

## User Experience

### Setup Flow
```
1. User installs extension
2. Extension: "Create a master password to encrypt your data"
3. User creates password (never sent to server)
4. Extension derives encryption key from password
5. Extension: "Your browsing data will be encrypted with this password.
              We cannot recover it if you forget. Please back it up."
6. User backs up encryption key
7. Encryption enabled ✅
```

### Daily Use
```
User browses → Extension encrypts → Server stores encrypted blob
User opens dashboard → Extension fetches encrypted blob → Decrypts locally → Shows insights
```

**Server never sees plaintext data.**

### Multi-Device Sync
```
Device A: Has master key
Device B (new): Needs master key

Option 1: Enter master password on Device B
Option 2: Scan QR code from Device A
Option 3: Import backup key

Key syncs between devices via secure channel (end-to-end encrypted)
Server NEVER handles keys
```

---

## Compliance & Legal

### GDPR Compliance
- ✅ Right to be forgotten: Delete all encrypted data
- ✅ Data portability: Export encrypted blobs
- ✅ Minimal data collection: Only encrypted blobs + metadata
- ✅ Privacy by design: Zero-knowledge architecture
- ✅ Data controller: User controls encryption keys

### Warrant Canary
- Publicly state if we've received legal requests
- Update monthly
- If canary stops: We received secret request
- But: Data is encrypted, we can't decrypt it

### Terms of Service Highlights
```
"We use zero-knowledge encryption. This means:
  - We cannot read your browsing history
  - We cannot recover your password
  - We cannot decrypt your data
  - If you lose your password, your data is permanently lost
  - This is a feature, not a bug - your privacy is absolute"
```

---

## Migration from Phase 1

### For Existing Users
```
1. Phase 1 (Current): Data stored in plaintext
2. Phase 2 Migration:
   a. Generate encryption key for user
   b. Encrypt all existing data
   c. Replace plaintext with encrypted blobs
   d. Delete plaintext data
   e. Verify encryption successful
3. User must set master password
4. Backup encryption key
5. Migration complete ✅
```

**Migration Job:**
```ruby
class MigrateToEncryptedStorageJob < ApplicationJob
  def perform(user_id)
    user = User.find(user_id)

    # Generate temporary encryption key for migration
    # User will replace with password-based key on next login
    temp_key = generate_migration_key(user)

    # Encrypt all page visits
    user.page_visits.find_each do |visit|
      encrypted_data = encrypt_record(visit, temp_key)
      EncryptedBrowsingData.create!(
        user: user,
        encrypted_payload: encrypted_data[:payload],
        nonce: encrypted_data[:nonce],
        auth_tag: encrypted_data[:tag],
        data_type: 'page_visit',
        client_checksum: compute_checksum(visit)
      )
    end

    # Delete plaintext after verification
    user.page_visits.delete_all if verify_migration_complete(user)

    # Notify user to set master password
    UserMailer.encryption_migration_complete(user).deliver_later
  end
end
```

---

## Next Steps

1. **Review this architecture** - Does it meet security requirements?
2. **Choose encryption strategy** - PBKDF2 vs device-specific keys?
3. **Plan migration** - How to migrate existing Phase 1 data?
4. **Third-party audit** - Engage security firm?
5. **Legal review** - Terms of service, privacy policy
6. **Create detailed docs** - Implementation guides for each component

---

**Status:** Proposed Security Architecture
**Priority:** CRITICAL - Must complete before any feature development
**Estimated Effort:** 4-6 weeks
**Last Updated:** 2025-10-16
