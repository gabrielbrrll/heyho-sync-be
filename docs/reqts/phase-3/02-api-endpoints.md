# Phase 3: API Endpoints

## Overview

This document specifies all REST API endpoints needed for Phase 3 features.

**Base URL:** `/api/v1`

**Authentication:** All endpoints require JWT authentication via `Authorization: Bearer <token>` header.

---

## Pattern Detection Endpoints

### 1. Get Hoarder Tabs

**Endpoint:** `GET /api/v1/patterns/hoarder-tabs`

**Description:** Detect tabs that have been open for a long time with minimal engagement.

**Query Parameters:**
```
min_duration      - Minimum duration in seconds (default: 300)
max_engagement    - Maximum engagement rate (default: 0.05)
limit             - Max results to return (default: 50, max: 100)
offset            - Pagination offset (default: 0)
```

**Request Example:**
```http
GET /api/v1/patterns/hoarder-tabs?min_duration=600&limit=10
Authorization: Bearer eyJhbGci...
```

**Response 200:**
```json
{
  "success": true,
  "data": {
    "hoarder_tabs": [
      {
        "id": "pv_1760649462365_1215",
        "url": "https://docs.google.com/spreadsheets/...",
        "title": "Important Spreadsheet",
        "domain": "docs.google.com",
        "duration_seconds": 94355,
        "engagement_rate": 0.001,
        "visited_at": "2025-10-13T12:10:38Z",
        "hours_open": 26.2,
        "suggestion": "You've had this open for 26 hours but only engaged for 2 minutes."
      }
    ],
    "total_count": 14,
    "pagination": {
      "limit": 10,
      "offset": 0,
      "has_more": true
    }
  }
}
```

---

### 2. Get Serial Openers

**Endpoint:** `GET /api/v1/patterns/serial-openers`

**Description:** Detect domains/URLs that user repeatedly opens but never finishes reading.

**Query Parameters:**
```
min_opens         - Minimum number of opens (default: 3)
max_duration      - Maximum duration per visit in seconds (default: 120)
lookback_days     - Days to look back (default: 30)
limit             - Max results (default: 50)
offset            - Pagination offset (default: 0)
```

**Request Example:**
```http
GET /api/v1/patterns/serial-openers?min_opens=5
Authorization: Bearer eyJhbGci...
```

**Response 200:**
```json
{
  "success": true,
  "data": {
    "serial_openers": [
      {
        "domain": "medium.com",
        "open_count": 12,
        "avg_duration_seconds": 45.3,
        "last_opened": "2025-10-16T14:30:00Z",
        "example_urls": [
          "https://medium.com/@author/article-1",
          "https://medium.com/@author/article-2"
        ],
        "suggestion": "You've opened Medium articles 12 times this month but spent less than 1 min each time."
      }
    ],
    "total_count": 52,
    "pagination": {
      "limit": 50,
      "offset": 0,
      "has_more": true
    }
  }
}
```

---

### 3. Get Research Sessions

**Endpoint:** `GET /api/v1/patterns/research-sessions`

**Description:** Detect browsing sessions where user opened many related tabs in a short time.

**Query Parameters:**
```
min_tabs          - Minimum tabs in session (default: 5)
time_window_min   - Time window in minutes (default: 10)
lookback_days     - Days to look back (default: 7)
limit             - Max results (default: 50)
offset            - Pagination offset (default: 0)
```

**Request Example:**
```http
GET /api/v1/patterns/research-sessions?min_tabs=8
Authorization: Bearer eyJhbGci...
```

**Response 200:**
```json
{
  "success": true,
  "data": {
    "research_sessions": [
      {
        "domain": "stackoverflow.com",
        "tab_count": 12,
        "session_start": "2025-10-16T14:00:00Z",
        "session_end": "2025-10-16T14:35:00Z",
        "duration_minutes": 35,
        "tab_ids": ["pv_123", "pv_124", "pv_125"],
        "auto_name": "StackOverflow Research - Oct 16, 2:00 PM",
        "suggestion": "You opened 12 StackOverflow tabs in 35 minutes. Save this research session?"
      }
    ],
    "total_count": 101,
    "pagination": {
      "limit": 50,
      "offset": 0,
      "has_more": true
    }
  }
}
```

---

## Reading List Endpoints

### 4. Get Reading List

**Endpoint:** `GET /api/v1/reading-list`

**Description:** Get user's reading list items.

**Query Parameters:**
```
status            - Filter by status: 'unread', 'reading', 'completed', 'dismissed' (optional)
added_from        - Filter by source: 'hoarder_detection', 'manual_save', etc. (optional)
scheduled         - Filter scheduled items: 'true', 'false' (optional)
tags              - Filter by tags: comma-separated (optional)
limit             - Max results (default: 50)
offset            - Pagination offset (default: 0)
sort              - Sort by: 'added_at', 'scheduled_for', 'title' (default: 'added_at')
order             - Order: 'asc', 'desc' (default: 'desc')
```

**Request Example:**
```http
GET /api/v1/reading-list?status=unread&limit=20
Authorization: Bearer eyJhbGci...
```

**Response 200:**
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": 123,
        "url": "https://example.com/article",
        "title": "How to Build Better Apps",
        "domain": "example.com",
        "status": "unread",
        "added_at": "2025-10-15T10:00:00Z",
        "added_from": "hoarder_detection",
        "estimated_read_time": 480,
        "tags": ["productivity", "development"],
        "notes": "Check out the section on testing",
        "scheduled_for": "2025-10-17T14:00:00Z"
      }
    ],
    "stats": {
      "total_unread": 23,
      "total_reading": 2,
      "total_completed": 45,
      "completion_rate": 0.64
    },
    "pagination": {
      "limit": 20,
      "offset": 0,
      "total": 23,
      "has_more": true
    }
  }
}
```

---

### 5. Add to Reading List

**Endpoint:** `POST /api/v1/reading-list`

**Description:** Add a single item to reading list.

**Request Body:**
```json
{
  "url": "https://example.com/article",
  "title": "Article Title",
  "domain": "example.com",
  "page_visit_id": "pv_123456",
  "added_from": "manual_save",
  "estimated_read_time": 420,
  "notes": "Important for project X",
  "tags": ["work", "research"],
  "scheduled_for": "2025-10-17T14:00:00Z"
}
```

**Required Fields:**
- `url` (string)

**Optional Fields:**
- `title` (string)
- `domain` (string) - Auto-extracted if not provided
- `page_visit_id` (string)
- `added_from` (string)
- `estimated_read_time` (integer)
- `notes` (text)
- `tags` (array of strings)
- `scheduled_for` (timestamp)

**Response 201:**
```json
{
  "success": true,
  "message": "Added to reading list",
  "data": {
    "id": 124,
    "url": "https://example.com/article",
    "title": "Article Title",
    "status": "unread",
    "added_at": "2025-10-16T15:30:00Z"
  }
}
```

**Response 422 (Duplicate):**
```json
{
  "success": false,
  "message": "Item already in reading list",
  "errors": ["URL has already been saved"]
}
```

---

### 6. Bulk Add to Reading List

**Endpoint:** `POST /api/v1/reading-list/bulk`

**Description:** Add multiple items at once (e.g., from hoarder tab detection).

**Request Body:**
```json
{
  "items": [
    {
      "url": "https://example.com/article1",
      "title": "Article 1",
      "page_visit_id": "pv_123",
      "added_from": "hoarder_detection"
    },
    {
      "url": "https://example.com/article2",
      "title": "Article 2",
      "page_visit_id": "pv_124",
      "added_from": "hoarder_detection"
    }
  ],
  "skip_duplicates": true
}
```

**Response 201:**
```json
{
  "success": true,
  "message": "Added 2 items to reading list",
  "data": {
    "created": 2,
    "skipped": 0,
    "errors": 0,
    "items": [
      { "id": 125, "url": "https://example.com/article1", "status": "created" },
      { "id": 126, "url": "https://example.com/article2", "status": "created" }
    ]
  }
}
```

---

### 7. Update Reading List Item

**Endpoint:** `PATCH /api/v1/reading-list/:id`

**Description:** Update status, notes, tags, or schedule.

**Request Body:**
```json
{
  "status": "completed",
  "notes": "Great insights on performance optimization",
  "tags": ["performance", "optimization"],
  "scheduled_for": null
}
```

**Response 200:**
```json
{
  "success": true,
  "message": "Reading list item updated",
  "data": {
    "id": 123,
    "status": "completed",
    "completed_at": "2025-10-16T15:45:00Z"
  }
}
```

**Response 404:**
```json
{
  "success": false,
  "message": "Reading list item not found"
}
```

---

### 8. Delete Reading List Item

**Endpoint:** `DELETE /api/v1/reading-list/:id`

**Description:** Remove item from reading list.

**Response 200:**
```json
{
  "success": true,
  "message": "Removed from reading list"
}
```

---

## Research Session Endpoints

### 9. Get Research Sessions

**Endpoint:** `GET /api/v1/research-sessions`

**Description:** Get user's research sessions (detected or saved).

**Query Parameters:**
```
status            - Filter by status: 'detected', 'saved', 'restored', 'dismissed' (optional)
domain            - Filter by domain (optional)
limit             - Max results (default: 50)
offset            - Pagination offset (default: 0)
sort              - Sort by: 'session_start', 'tab_count' (default: 'session_start')
order             - Order: 'asc', 'desc' (default: 'desc')
```

**Request Example:**
```http
GET /api/v1/research-sessions?status=detected&limit=10
Authorization: Bearer eyJhbGci...
```

**Response 200:**
```json
{
  "success": true,
  "data": {
    "sessions": [
      {
        "id": 45,
        "session_name": "React Testing Research - Oct 16, 2:30 PM",
        "session_start": "2025-10-16T14:30:00Z",
        "session_end": "2025-10-16T15:15:00Z",
        "tab_count": 8,
        "primary_domain": "stackoverflow.com",
        "domains": ["stackoverflow.com", "github.com", "reactjs.org"],
        "topics": ["react", "testing", "hooks"],
        "total_duration_seconds": 2700,
        "avg_engagement_rate": 0.62,
        "status": "detected",
        "tabs_preview": [
          {
            "url": "https://stackoverflow.com/questions/...",
            "title": "How to test React hooks"
          }
        ]
      }
    ],
    "pagination": {
      "limit": 10,
      "offset": 0,
      "total": 101,
      "has_more": true
    }
  }
}
```

---

### 10. Get Research Session Detail

**Endpoint:** `GET /api/v1/research-sessions/:id`

**Description:** Get full details of a research session including all tabs.

**Response 200:**
```json
{
  "success": true,
  "data": {
    "id": 45,
    "session_name": "React Testing Research - Oct 16, 2:30 PM",
    "session_start": "2025-10-16T14:30:00Z",
    "session_end": "2025-10-16T15:15:00Z",
    "tab_count": 8,
    "primary_domain": "stackoverflow.com",
    "domains": ["stackoverflow.com", "github.com", "reactjs.org"],
    "topics": ["react", "testing", "hooks"],
    "status": "detected",
    "tabs": [
      {
        "id": 1,
        "page_visit_id": "pv_123",
        "url": "https://stackoverflow.com/questions/...",
        "title": "How to test React hooks",
        "domain": "stackoverflow.com",
        "tab_order": 1
      },
      {
        "id": 2,
        "page_visit_id": "pv_124",
        "url": "https://github.com/testing-library/react-hooks-testing-library",
        "title": "React Hooks Testing Library",
        "domain": "github.com",
        "tab_order": 2
      }
    ]
  }
}
```

---

### 11. Save Research Session

**Endpoint:** `POST /api/v1/research-sessions/:id/save`

**Description:** Mark a detected session as "saved" by the user.

**Request Body (Optional):**
```json
{
  "session_name": "My Custom Name for Session"
}
```

**Response 200:**
```json
{
  "success": true,
  "message": "Research session saved",
  "data": {
    "id": 45,
    "status": "saved",
    "saved_at": "2025-10-16T16:00:00Z"
  }
}
```

---

### 12. Restore Research Session

**Endpoint:** `POST /api/v1/research-sessions/:id/restore`

**Description:** Get tab URLs for restoring in browser.

**Response 200:**
```json
{
  "success": true,
  "message": "Research session restored",
  "data": {
    "id": 45,
    "session_name": "React Testing Research - Oct 16, 2:30 PM",
    "tab_count": 8,
    "tabs": [
      {
        "url": "https://stackoverflow.com/questions/...",
        "title": "How to test React hooks",
        "order": 1
      },
      {
        "url": "https://github.com/testing-library/react-hooks-testing-library",
        "title": "React Hooks Testing Library",
        "order": 2
      }
    ],
    "restore_count": 1,
    "last_restored_at": "2025-10-16T16:05:00Z"
  }
}
```

---

### 13. Create Research Session (Manual)

**Endpoint:** `POST /api/v1/research-sessions`

**Description:** Manually create a research session from tab IDs.

**Request Body:**
```json
{
  "session_name": "My Research Session",
  "page_visit_ids": ["pv_123", "pv_124", "pv_125"]
}
```

**Response 201:**
```json
{
  "success": true,
  "message": "Research session created",
  "data": {
    "id": 46,
    "session_name": "My Research Session",
    "tab_count": 3,
    "status": "saved"
  }
}
```

---

### 14. Update Research Session

**Endpoint:** `PATCH /api/v1/research-sessions/:id`

**Description:** Update session name or status.

**Request Body:**
```json
{
  "session_name": "Updated Session Name",
  "status": "dismissed"
}
```

**Response 200:**
```json
{
  "success": true,
  "message": "Research session updated"
}
```

---

### 15. Delete Research Session

**Endpoint:** `DELETE /api/v1/research-sessions/:id`

**Description:** Delete a research session and its tabs.

**Response 200:**
```json
{
  "success": true,
  "message": "Research session deleted"
}
```

---

## User Preferences Endpoints

### 16. Get Pattern Detection Preferences

**Endpoint:** `GET /api/v1/preferences/pattern-detection`

**Description:** Get user's pattern detection preferences.

**Response 200:**
```json
{
  "success": true,
  "data": {
    "hoarder_detection_enabled": true,
    "hoarder_min_duration_seconds": 300,
    "hoarder_max_engagement_rate": 0.05,
    "serial_opener_detection_enabled": true,
    "serial_opener_min_opens": 3,
    "research_session_detection_enabled": true,
    "research_session_min_tabs": 5,
    "notifications_enabled": true,
    "notification_frequency": "daily",
    "excluded_domains": ["bank.com", "private.com"]
  }
}
```

---

### 17. Update Pattern Detection Preferences

**Endpoint:** `PATCH /api/v1/preferences/pattern-detection`

**Description:** Update user's preferences.

**Request Body:**
```json
{
  "hoarder_min_duration_seconds": 600,
  "notifications_enabled": false,
  "excluded_domains": ["bank.com", "private.com", "medical.com"]
}
```

**Response 200:**
```json
{
  "success": true,
  "message": "Preferences updated"
}
```

---

## Error Responses

### Standard Error Format
```json
{
  "success": false,
  "message": "Error description",
  "errors": ["Detailed error 1", "Detailed error 2"]
}
```

### Common HTTP Status Codes
- `200 OK` - Successful GET/PATCH/DELETE
- `201 Created` - Successful POST
- `400 Bad Request` - Invalid parameters
- `401 Unauthorized` - Missing/invalid authentication
- `404 Not Found` - Resource not found
- `422 Unprocessable Entity` - Validation errors
- `500 Internal Server Error` - Server error

---

## Rate Limiting

**Limits:**
- Pattern detection endpoints: 60 requests/minute
- Reading list endpoints: 120 requests/minute
- Research session endpoints: 60 requests/minute

**Headers:**
```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1697472000
```

---

## API Versioning

All endpoints use `/api/v1` prefix. Future versions will use `/api/v2`, etc.

No breaking changes will be made to v1 endpoints without deprecation notice.

---

## Testing Endpoints

### Postman Collection
All endpoints will be added to: `docs/postman/Phase3-ResourcePatterns.postman_collection.json`

### cURL Examples
See `03-detection-logic.md` for detailed cURL examples.

---

**Status:** Ready for Implementation
**Last Updated:** 2025-10-16
