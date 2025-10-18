# Phase 3: Browser Extension Changes

## Overview

Minimal changes needed to browser extension. Most detection happens server-side using existing data.

---

## Required Changes

### 1. API Client Updates

Add new API endpoints to existing client:

**File:** `src/api/client.js` (or equivalent)

```javascript
// Pattern Detection APIs
export async function getHoarderTabs(params = {}) {
  return apiRequest('/api/v1/patterns/hoarder-tabs', {
    method: 'GET',
    params: {
      min_duration: params.minDuration || 300,
      max_engagement: params.maxEngagement || 0.05,
      limit: params.limit || 50
    }
  });
}

export async function getSerialOpeners(params = {}) {
  return apiRequest('/api/v1/patterns/serial-openers', {
    method: 'GET',
    params: {
      min_opens: params.minOpens || 3,
      max_duration: params.maxDuration || 120,
      lookback_days: params.lookbackDays || 30,
      limit: params.limit || 50
    }
  });
}

export async function getResearchSessions(params = {}) {
  return apiRequest('/api/v1/patterns/research-sessions', {
    method: 'GET',
    params: {
      min_tabs: params.minTabs || 5,
      time_window_min: params.timeWindowMin || 10,
      lookback_days: params.lookbackDays || 7,
      limit: params.limit || 50
    }
  });
}

// Reading List APIs
export async function getReadingList(params = {}) {
  return apiRequest('/api/v1/reading-list', {
    method: 'GET',
    params
  });
}

export async function addToReadingList(item) {
  return apiRequest('/api/v1/reading-list', {
    method: 'POST',
    body: { reading_list_item: item }
  });
}

export async function bulkAddToReadingList(items, skipDuplicates = true) {
  return apiRequest('/api/v1/reading-list/bulk', {
    method: 'POST',
    body: { items, skip_duplicates: skipDuplicates }
  });
}

export async function updateReadingListItem(id, updates) {
  return apiRequest(`/api/v1/reading-list/${id}`, {
    method: 'PATCH',
    body: updates
  });
}

// Research Session APIs
export async function getResearchSessionsList(params = {}) {
  return apiRequest('/api/v1/research-sessions', {
    method: 'GET',
    params
  });
}

export async function getResearchSessionDetail(id) {
  return apiRequest(`/api/v1/research-sessions/${id}`, {
    method: 'GET'
  });
}

export async function restoreResearchSession(id) {
  return apiRequest(`/api/v1/research-sessions/${id}/restore`, {
    method: 'POST'
  });
}

export async function saveResearchSession(id, customName = null) {
  return apiRequest(`/api/v1/research-sessions/${id}/save`, {
    method: 'POST',
    body: customName ? { session_name: customName } : {}
  });
}
```

---

### 2. Extension Popup UI

Add new section to popup showing detected patterns:

**File:** `src/popup/ResourcePatterns.jsx` (new file)

```jsx
import React, { useEffect, useState } from 'react';
import { getHoarderTabs, getSerialOpeners, getResearchSessions } from '../api/client';

export function ResourcePatterns() {
  const [patterns, setPatterns] = useState({
    hoarderCount: 0,
    serialOpenerCount: 0,
    researchSessionCount: 0,
    loading: true
  });

  useEffect(() => {
    loadPatternCounts();
  }, []);

  async function loadPatternCounts() {
    try {
      const [hoarder, serial, research] = await Promise.all([
        getHoarderTabs({ limit: 1 }),
        getSerialOpeners({ limit: 1 }),
        getResearchSessions({ limit: 1 })
      ]);

      setPatterns({
        hoarderCount: hoarder.data.total_count || 0,
        serialOpenerCount: serial.data.total_count || 0,
        researchSessionCount: research.data.total_count || 0,
        loading: false
      });
    } catch (error) {
      console.error('Failed to load patterns:', error);
      setPatterns(prev => ({ ...prev, loading: false }));
    }
  }

  if (patterns.loading) {
    return <div>Loading patterns...</div>;
  }

  return (
    <div className="resource-patterns">
      <h3>Smart Resource Manager</h3>

      <div className="pattern-item" onClick={() => openPatternView('hoarder')}>
        <span className="icon">📚</span>
        <span className="label">Hoarder Tabs</span>
        <span className="count">{patterns.hoarderCount}</span>
      </div>

      <div className="pattern-item" onClick={() => openPatternView('serial')}>
        <span className="icon">🔄</span>
        <span className="label">Serial Openers</span>
        <span className="count">{patterns.serialOpenerCount}</span>
      </div>

      <div className="pattern-item" onClick={() => openPatternView('research')}>
        <span className="icon">🐇</span>
        <span className="label">Research Sessions</span>
        <span className="count">{patterns.researchSessionCount}</span>
      </div>
    </div>
  );
}

function openPatternView(type) {
  // Open full view in new tab or side panel
  chrome.tabs.create({
    url: chrome.runtime.getURL(`dashboard.html#/patterns/${type}`)
  });
}
```

---

### 3. Tab Restoration

Add functionality to restore research sessions:

**File:** `src/background/sessionRestoration.js` (new file)

```javascript
// Restore research session tabs
export async function restoreResearchSession(sessionId) {
  try {
    const response = await restoreResearchSession(sessionId);
    const { tabs } = response.data;

    // Open all tabs in order
    const openedTabs = [];
    for (const tab of tabs) {
      const newTab = await chrome.tabs.create({
        url: tab.url,
        active: false // Don't steal focus
      });
      openedTabs.push(newTab);
    }

    // Show notification
    await chrome.notifications.create({
      type: 'basic',
      iconUrl: chrome.runtime.getURL('icons/icon128.png'),
      title: 'Research Session Restored',
      message: `Opened ${tabs.length} tabs from "${response.data.session_name}"`
    });

    return openedTabs;
  } catch (error) {
    console.error('Failed to restore session:', error);
    await chrome.notifications.create({
      type: 'basic',
      iconUrl: chrome.runtime.getURL('icons/icon128.png'),
      title: 'Restoration Failed',
      message: 'Could not restore research session. Please try again.'
    });
    throw error;
  }
}

// Restore with confirmation
export async function restoreSessionWithConfirmation(sessionId, sessionName, tabCount) {
  const confirmed = confirm(
    `Restore "${sessionName}"?\n\nThis will open ${tabCount} tabs.`
  );

  if (!confirmed) {
    return null;
  }

  return restoreResearchSession(sessionId);
}
```

---

### 4. Reading List Actions

Add quick actions for saving to reading list:

**File:** `src/content/readingListActions.js` (new file)

```javascript
// Context menu for adding current tab to reading list
chrome.contextMenus.create({
  id: 'add-to-reading-list',
  title: 'Add to Reading List',
  contexts: ['page']
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId === 'add-to-reading-list') {
    try {
      await addToReadingList({
        url: tab.url,
        title: tab.title,
        domain: new URL(tab.url).hostname.replace(/^www\./, ''),
        added_from: 'manual_save'
      });

      await chrome.notifications.create({
        type: 'basic',
        iconUrl: chrome.runtime.getURL('icons/icon128.png'),
        title: 'Added to Reading List',
        message: `Saved: ${tab.title}`
      });
    } catch (error) {
      console.error('Failed to add to reading list:', error);
    }
  }
});

// Keyboard shortcut
chrome.commands.onCommand.addListener(async (command) => {
  if (command === 'add-to-reading-list') {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });

    await addToReadingList({
      url: tab.url,
      title: tab.title,
      domain: new URL(tab.url).hostname.replace(/^www\./, ''),
      added_from: 'manual_save'
    });
  }
});
```

**Add to manifest.json:**
```json
{
  "commands": {
    "add-to-reading-list": {
      "suggested_key": {
        "default": "Ctrl+Shift+S",
        "mac": "Command+Shift+S"
      },
      "description": "Add current tab to reading list"
    }
  },
  "permissions": [
    "contextMenus",
    "notifications"
  ]
}
```

---

### 5. Badge Notifications

Show pattern count in extension badge:

**File:** `src/background/badgeUpdater.js`

```javascript
// Update badge with pattern count
export async function updatePatternBadge() {
  try {
    const [hoarder, serial, research] = await Promise.all([
      getHoarderTabs({ limit: 1 }),
      getSerialOpeners({ limit: 1 }),
      getResearchSessions({ limit: 1 })
    ]);

    const totalCount =
      (hoarder.data.total_count || 0) +
      (serial.data.total_count || 0) +
      (research.data.total_count || 0);

    if (totalCount > 0) {
      await chrome.action.setBadgeText({ text: totalCount.toString() });
      await chrome.action.setBadgeBackgroundColor({ color: '#FF6B6B' });
      await chrome.action.setTitle({
        title: `${totalCount} patterns detected`
      });
    } else {
      await chrome.action.setBadgeText({ text: '' });
    }
  } catch (error) {
    console.error('Failed to update badge:', error);
  }
}

// Update every 5 minutes
chrome.alarms.create('update-pattern-badge', { periodInMinutes: 5 });

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'update-pattern-badge') {
    updatePatternBadge();
  }
});

// Update on extension startup
updatePatternBadge();
```

---

## Optional Enhancements (Phase 4)

### 1. Inline Suggestions

Show suggestions directly in browser when patterns detected:

```javascript
// Content script to show inline suggestion
if (detectedAsHoarderTab) {
  const banner = document.createElement('div');
  banner.className = 'heyho-suggestion-banner';
  banner.innerHTML = `
    <div>📚 You've had this tab open for 3 hours with minimal engagement.</div>
    <button id="save-to-reading-list">Save for Later</button>
    <button id="dismiss">Dismiss</button>
  `;
  document.body.insertBefore(banner, document.body.firstChild);
}
```

### 2. Smart Reminders

Remind user about unread items during idle time:

```javascript
// Detect idle time and show reminder
chrome.idle.onStateChanged.addListener(async (state) => {
  if (state === 'idle') {
    const readingList = await getReadingList({ status: 'unread', limit: 5 });

    if (readingList.data.items.length > 0) {
      await chrome.notifications.create({
        type: 'basic',
        title: 'Reading List Reminder',
        message: `You have ${readingList.data.items.length} unread items. Time to catch up?`,
        buttons: [{ title: 'Open Reading List' }]
      });
    }
  }
});
```

---

## Testing

### Manual Testing

1. **Pattern Detection:**
   - Open extension popup
   - Verify pattern counts display correctly
   - Click each pattern type to open dashboard

2. **Reading List:**
   - Right-click on page → "Add to Reading List"
   - Use keyboard shortcut (Ctrl+Shift+S)
   - Verify notification appears

3. **Session Restoration:**
   - Restore a research session from dashboard
   - Verify all tabs open in correct order
   - Verify notification shows count

### Automated Testing

```javascript
// tests/api/patterns.test.js
describe('Pattern Detection API', () => {
  it('fetches hoarder tabs', async () => {
    const result = await getHoarderTabs();
    expect(result.success).toBe(true);
    expect(result.data.hoarder_tabs).toBeInstanceOf(Array);
  });

  it('fetches serial openers', async () => {
    const result = await getSerialOpeners();
    expect(result.success).toBe(true);
    expect(result.data.serial_openers).toBeInstanceOf(Array);
  });
});
```

---

## Deployment

### Build & Test

```bash
cd apps/browser-extension
npm install
npm run build
npm test
```

### Load in Browser

1. Open `chrome://extensions/`
2. Enable "Developer mode"
3. Click "Load unpacked"
4. Select `dist/` folder

### Verify

- Extension icon shows badge with count
- Popup displays pattern sections
- Context menu has "Add to Reading List"
- Keyboard shortcut works

---

**Status:** Ready for Implementation
**Last Updated:** 2025-10-16
