# Feature: Sound Event RSS Feed Monitor

Play sounds for new RSS feed items and updates.

## Summary

Monitor RSS feeds for new articles and updates, playing sounds when new content is detected.

## Motivation

- News alerts
- Blog update notifications
- Feed change detection
- Content awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### RSS Feed Events

| Event | Description | Example |
|-------|-------------|---------|
| New Item | New article posted | Blog post |
| Updated Feed | Feed modified | Updated content |
| Error | Feed fetch failed | 404 error |
| Subscription | New subscription | Added feed |

### Configuration

```go
type RSSFeedMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    Feeds            []string          `json:"feeds"` // Feed URLs
    CheckInterval    int               `json:"check_interval_minutes"` // 30 default
    SoundOnNewItem   bool              `json:"sound_on_new_item"`
    SoundOnError     bool              `json:"sound_on_error"`
    MaxItemsPerFeed  int               `json:"max_items_per_feed"` // 10 default
    Sounds           map[string]string `json:"sounds"`
}

type RSSFeedEvent struct {
    FeedTitle   string
    FeedURL     string
    ItemTitle   string
    ItemURL     string
    PublishedAt time.Time
    EventType   string // "new_item", "error"
}
```

### Commands

```bash
/ccbell:rss status                   # Show RSS status
/ccbell:rss add https://example.com/feed.xml
/ccbell:rss remove https://example.com/feed.xml
/ccbell:rss sound new <sound>
/ccbell:rss test                     # Test RSS sounds
```

### Output

```
$ ccbell:rss status

=== Sound Event RSS Feed Monitor ===

Status: Enabled
Check Interval: 30 minutes

Watched Feeds: 5

[1] Tech Blog
    URL: https://techblog.com/feed.xml
    Last Check: 5 min ago
    New Items: 2
    Last Item: "New Feature Released"
    Sound: bundled:stop

[2] News Feed
    URL: https://news.com/rss
    Last Check: 5 min ago
    New Items: 5
    Last Item: "Breaking: Market Update"
    Sound: bundled:stop

[3] Dev Blog
    URL: https://devblog.com/feed
    Last Check: 30 min ago
    New Items: 0
    Sound: bundled:stop

Recent New Items:
  [1] Tech Blog: New Feature Released (10 min ago)
       https://techblog.com/posts/new-feature
  [2] News Feed: Breaking: Market Update (15 min ago)
       https://news.com/articles/market
  [3] Tech Blog: Bug Fixes (1 hour ago)
       https://techblog.com/posts/fixes

Sound Settings:
  New Item: bundled:stop
  Error: bundled:stop

[Configure] [Add Feed] [Test All]
```

---

## Audio Player Compatibility

RSS feed monitoring doesn't play sounds directly:
- Monitoring feature using HTTP client
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### RSS Feed Monitor

```go
type RSSFeedMonitor struct {
    config           *RSSFeedMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    feedState        map[string]*FeedState
    lastItemGUID     map[string]string // feed URL -> last item GUID
}

type FeedState struct {
    URL          string
    Title        string
    LastCheck    time.Time
    ItemCount    int
    ErrorMessage string
}
```

```go
func (m *RSSFeedMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.feedState = make(map[string]*FeedState)
    m.lastItemGUID = make(map[string]string)
    go m.monitor()
}

func (m *RSSFeedMonitor) monitor() {
    interval := time.Duration(m.config.CheckInterval) * time.Minute
    ticker := time.NewTicker(interval)
    defer ticker.Stop()

    // Initial check
    m.checkAllFeeds()

    for {
        select {
        case <-ticker.C:
            m.checkAllFeeds()
        case <-m.stopCh:
            return
        }
    }
}

func (m *RSSFeedMonitor) checkAllFeeds() {
    for _, feedURL := range m.config.Feeds {
        m.checkFeed(feedURL)
    }
}

func (m *RSSFeedMonitor) checkFeed(feedURL string) {
    state := m.feedState[feedURL]
    if state == nil {
        state = &FeedState{URL: feedURL}
        m.feedState[feedURL] = state
    }

    // Fetch feed
    client := &http.Client{
        Timeout: 30 * time.Second,
    }

    resp, err := client.Get(feedURL)
    if err != nil {
        state.ErrorMessage = err.Error()
        m.onFeedError(feedURL, err.Error())
        return
    }
    defer resp.Body.Close()

    if resp.StatusCode != 200 {
        state.ErrorMessage = fmt.Sprintf("HTTP %d", resp.StatusCode)
        m.onFeedError(feedURL, state.ErrorMessage)
        return
    }

    // Parse feed
    items, err := m.parseFeed(resp.Body)
    if err != nil {
        state.ErrorMessage = err.Error()
        m.onFeedError(feedURL, err.Error())
        return
    }

    state.LastCheck = time.Now()
    state.ItemCount = len(items)

    // Get feed title from items (or empty for RSS without channel)
    if len(items) > 0 {
        state.Title = items[0].FeedTitle
    }

    // Check for new items
    lastGUID := m.lastItemGUID[feedURL]
    newItems := m.findNewItems(items, lastGUID)

    if len(newItems) > 0 {
        // Update last GUID
        m.lastItemGUID[feedURL] = newItems[0].GUID

        state.Title = newItems[0].FeedTitle
        for _, item := range newItems {
            m.onNewItem(item)
        }
    }

    state.ErrorMessage = ""
}

func (m *RSSFeedMonitor) parseFeed(body io.Reader) ([]*RSSItem, error) {
    var items []*RSSItem

    // Try XML parsing
    decoder := xml.NewDecoder(body)

    for {
        token, err := decoder.Token()
        if err == io.EOF {
            break
        }
        if err != nil {
            return items, err
        }

        switch elem := token.(type) {
        case xml.StartElement:
            if elem.Name.Local == "item" {
                item, err := m.parseItem(decoder)
                if err == nil {
                    items = append(items, item)
                }
            }
        }
    }

    return items, nil
}

func (m *RSSFeedMonitor) parseItem(decoder *xml.Decoder) (*RSSItem, error) {
    item := &RSSItem{}

    for {
        token, err := decoder.Token()
        if err == io.EOF {
            break
        }
        if err != nil {
            return nil, err
        }

        switch elem := token.(type) {
        case xml.StartElement:
            switch elem.Name.Local {
            case "title":
                if content, err := decoder.TokenContent(); err == nil {
                    if text, ok := content.(string); ok {
                        item.Title = text
                    }
                }
            case "link":
                if content, err := decoder.TokenContent(); err == nil {
                    if text, ok := content.(string); ok {
                        item.URL = text
                    }
                }
            case "guid":
                if content, err := decoder.TokenContent(); err == nil {
                    if text, ok := content.(string); ok {
                        item.GUID = text
                    }
                }
            case "pubDate":
                if content, err := decoder.TokenContent(); err == nil {
                    if text, ok := content.(string); ok {
                        if t, err := time.Parse(time.RFC1123, text); err == nil {
                            item.PublishedAt = t
                        }
                    }
                }
            }
        case xml.EndElement:
            if elem.Name.Local == "item" {
                break
            }
        }
    }

    // Use URL as GUID if not provided
    if item.GUID == "" {
        item.GUID = item.URL
    }

    return item, nil
}

func (m *RSSFeedMonitor) findNewItems(items []*RSSItem, lastGUID string) []*RSSItem {
    var newItems []*RSSItem

    for _, item := range items {
        if item.GUID == lastGUID {
            break
        }
        newItems = append(newItems, item)
    }

    // Reverse to get chronological order (newest first)
    for i, j := 0, len(newItems)-1; i < j; i, j = i+1, j-1 {
        newItems[i], newItems[j] = newItems[j], newItems[i]
    }

    // Limit to max items
    if len(newItems) > m.config.MaxItemsPerFeed {
        newItems = newItems[:m.config.MaxItemsPerFeed]
    }

    return newItems
}

func (m *RSSFeedMonitor) onNewItem(item *RSSItem) {
    if !m.config.SoundOnNewItem {
        return
    }

    sound := m.config.Sounds["new_item"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *RSSFeedMonitor) onFeedError(feedURL, errorMsg string) {
    if !m.config.SoundOnError {
        return
    }

    sound := m.config.Sounds["error"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| net/http | Go Stdlib | Free | HTTP client |
| encoding/xml | Go Stdlib | Free | XML parsing |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Supported | Uses HTTP client |
| Linux | Supported | Uses HTTP client |
| Windows | Not Supported | ccbell only supports macOS/Linux |
