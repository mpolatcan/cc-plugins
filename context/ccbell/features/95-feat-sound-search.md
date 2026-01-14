# Feature: Sound Search

Search sounds by name, tags, or attributes.

## Summary

Find sounds quickly using powerful search capabilities.

## Motivation

- Find sounds quickly
- Search by attributes
- Filter and sort results

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Search Capabilities

| Feature | Description | Example |
|---------|-------------|---------|
| Text search | Search by name | "stop", "bell" |
| Tag search | Search by tags | "tag:alert" |
| Event filter | Filter by event | "event:stop" |
| Source filter | Filter by source | "source:bundled" |
| Duration filter | Filter by duration | "duration:<2s" |
| Sort | Sort results | "sort:popular" |

### Implementation

```go
type SearchQuery struct {
    Text       string   `json:"text"`
    Tags       []string `json:"tags"`
    Event      string   `json:"event"`
    Source     string   `json:"source"` // bundled, custom
    MinDuration float64 `json:"min_duration"`
    MaxDuration float64 `json:"max_duration"`
    SortBy     string   `json:"sort_by"` // name, duration, date, popular
    SortOrder  string   `json:"sort_order"` // asc, desc
    Limit      int      `json:"limit"`
    Offset     int      `json:"offset"`
}

type SearchResult struct {
    SoundID     string  `json:"sound_id"`
    SoundPath   string  `json:"sound_path"`
    Name        string  `json:"name"`
    Event       string  `json:"event"`
    Source      string  `json:"source"`
    Duration    float64 `json:"duration"`
    Tags        []string `json:"tags"`
    Score       float64 `json:"score"` // relevance score
}
```

### Commands

```bash
/ccbell:search bell              # Search for bell
/ccbell:search "notification"    # Search with quotes
/ccbell:search tag:alert         # Search by tag
/ccbell:search event:stop        # Filter by event
/ccbell:search source:bundled    # Bundled sounds only
/ccbell:search duration:<2s      # Short sounds
/ccbell:search --sort name       # Sort by name
/ccbell:search --limit 10        # Top 10 results
/ccbell:search --json            # JSON output
/ccbell:search --details         # Show details
```

### Output

```
$ ccbell:search bell

=== Sound Search: "bell" ===

Found: 8 sounds (12ms)

[1] bundled:stop ⭐
    Path: ~/.local/share/ccbell/sounds/bundled/stop.aiff
    Duration: 1.2s | Event: stop
    Tags: [notification, alert, system]
    [Play] [Use] [Details]

[2] custom:church-bell
    Path: ~/sounds/church-bell.aiff
    Duration: 3.4s | Event: -
    Tags: [bell, classic]
    [Play] [Use] [Details]

[3] bundled:subagent
    Path: ~/.local/share/ccbell/sounds/bundled/subagent.aiff
    Duration: 0.8s | Event: subagent
    Tags: [notification, complete]
    [Play] [Use] [Details]

Showing 3 of 8 results
[Prev] [Next] [Filter] [Sort]
```

---

## Audio Player Compatibility

Search doesn't play sounds:
- Discovery feature
- No player changes required

---

## Implementation

### Text Search

```go
func (s *SearchManager) Search(query *SearchQuery) ([]*SearchResult, error) {
    results := []*SearchResult{}

    // Get all sounds
    allSounds := s.getAllSounds()

    for _, sound := range allSounds {
        if s.matchesQuery(sound, query) {
            result := s.soundToResult(sound, query)
            results = append(results, result)
        }
    }

    // Sort results
    s.sortResults(results, query.SortBy, query.SortOrder)

    // Apply pagination
    if query.Limit > 0 {
        end := query.Offset + query.Limit
        if end > len(results) {
            end = len(results)
        }
        results = results[query.Offset:end]
    }

    return results, nil
}

func (s *SearchManager) matchesQuery(sound *SoundInfo, query *SearchQuery) bool {
    // Text match
    if query.Text != "" && !strings.Contains(strings.ToLower(sound.Name), strings.ToLower(query.Text)) {
        return false
    }

    // Tag match
    for _, tag := range query.Tags {
        if !contains(sound.Tags, tag) {
            return false
        }
    }

    // Event match
    if query.Event != "" && sound.Event != query.Event {
        return false
    }

    // Source match
    if query.Source != "" && sound.Source != query.Source {
        return false
    }

    // Duration match
    if query.MaxDuration > 0 && sound.Duration > query.MaxDuration {
        return false
    }

    return true
}
```

### Index Building

```go
func (s *SearchManager) buildIndex() {
    s.index = make(map[string][]string)

    sounds := s.getAllSounds()
    for _, sound := range sounds {
        // Index by name words
        for _, word := range strings.Fields(sound.Name) {
            s.index[word] = append(s.index[word], sound.ID)
        }

        // Index by tags
        for _, tag := range sound.Tags {
            s.index[tag] = append(s.index[tag], sound.ID)
        }

        // Index by event
        if sound.Event != "" {
            s.index["event:"+sound.Event] = append(s.index["event:"+sound.Event], sound.ID)
        }
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## References

### ccbell Implementation Research

- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound paths
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Sound references

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
