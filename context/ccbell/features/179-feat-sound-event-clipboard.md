# Feature: Sound Event Clipboard

Play sounds when clipboard content changes.

## Summary

Play different sounds based on clipboard content patterns or types.

## Motivation

- Clipboard awareness
- Content pattern alerts
- Workflow notification

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Clipboard Triggers

| Trigger | Description | Example |
|---------|-------------|---------|
| Type Change | Text/image/url | Copied image |
| Pattern Match | Regex match | Email, phone |
| Size Change | Content size | Large copy |
| URL Detected | URL in clipboard | https://... |

### Configuration

```go
type ClipboardConfig struct {
    Enabled     bool              `json:"enabled"`
    CheckInterval int            `json:"check_interval_ms"` // 500 default
    Triggers    []*ClipboardTrigger `json:"triggers"`
}

type ClipboardTrigger struct {
    ID          string  `json:"id"`
    Type        string  `json:"type"` // "text", "image", "url", "pattern", "size"
    Pattern     string  `json:"pattern,omitempty"` // Regex pattern
    MinSize     int     `json:"min_size,omitempty"` // Bytes
    MaxSize     int     `json:"max_size,omitempty"` // Bytes
    Sound       string  `json:"sound"`
    Volume      float64 `json:"volume,omitempty"`
    Enabled     bool    `json:"enabled"`
    IgnoreDuplicates bool `json:"ignore_duplicates"`
}

type ClipboardState struct {
    Content     string
    ContentType string // "text", "image", "url", "file"
    Size        int
    Hash        string
}
```

### Commands

```bash
/ccbell:clipboard status             # Show current clipboard
/ccbell:clipboard sound text <sound>
/ccbell:clipboard sound image <sound>
/ccbell:clipboard sound url <sound>
/ccbell:clipboard pattern "[a-zA-Z]+@[a-zA-Z]+\.[a-z]+" <sound>  # Email pattern
/ccbell:clipboard enable             # Enable clipboard monitoring
/ccbell:clipboard disable            # Disable clipboard monitoring
/ccbell:clipboard test               # Test clipboard sounds
```

### Output

```
$ ccbell:clipboard status

=== Sound Event Clipboard ===

Status: Enabled
Check Interval: 500ms

Current Clipboard:
  Type: Text
  Size: 45 bytes
  Preview: "hello@example.com"

Active Triggers:
  [1] Email Pattern
      Pattern: [a-zA-Z]+@[a-zA-Z]+\.[a-z]+
      Sound: bundled:stop
      Status: MATCHED

  [2] URL Detected
      Pattern: https?://
      Sound: bundled:stop
      Status: NOT MATCHED

  [3] Image Copy
      Type: image
      Sound: bundled:stop
      Status: NOT MATCHED

[Configure] [Test All] [Disable]
```

---

## Audio Player Compatibility

Clipboard monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Clipboard Monitoring

```go
type ClipboardManager struct {
    config   *ClipboardConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastHash string
    mutex    sync.Mutex
}

func (m *ClipboardManager) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    go m.monitor()
}

func (m *ClipboardManager) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Millisecond)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkClipboard()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ClipboardManager) checkClipboard() {
    content, contentType, size, err := m.getClipboardContent()
    if err != nil {
        log.Debug("Failed to get clipboard: %v", err)
        return
    }

    hash := m.hashContent(content)
    if hash == m.lastHash && m.config.IgnoreDuplicates {
        return
    }

    m.lastHash = hash

    for _, trigger := range m.config.Triggers {
        if !trigger.Enabled {
            continue
        }

        if m.checkTrigger(trigger, content, contentType, size) {
            m.playClipboardEvent(trigger)
        }
    }
}

func (m *ClipboardManager) getClipboardContent() (string, string, int, error) {
    // macOS: pbpaste
    cmd := exec.Command("pbpaste")
    output, err := cmd.Output()
    if err != nil {
        return "", "empty", 0, err
    }

    content := string(output)
    contentType := "text"

    // Check if it's a URL
    if matched, _ := regexp.MatchString(`^https?://`, content); matched {
        contentType = "url"
    }

    return content, contentType, len(output), nil
}

func (m *ClipboardManager) checkTrigger(trigger *ClipboardTrigger, content, contentType string, size int) bool {
    switch trigger.Type {
    case "text":
        return contentType == "text"
    case "url":
        return contentType == "url"
    case "image":
        // Check for image in clipboard (macOS: osascript)
        return m.isImageClipboard()
    case "pattern":
        matched, _ := regexp.MatchString(trigger.Pattern, content)
        return matched
    case "size":
        if trigger.MinSize > 0 && size < trigger.MinSize {
            return false
        }
        if trigger.MaxSize > 0 && size > trigger.MaxSize {
            return false
        }
        return true
    }
    return false
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| pbpaste | System Tool | Free | macOS clipboard |
| xclip | APT | Free | Linux clipboard |
| xsel | APT | Free | Linux clipboard |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Uses pbpaste |
| Linux | ✅ Supported | Uses xclip/xsel |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
