# Feature: Sound Event Clipboard Monitor

Play sounds for clipboard activity and content changes.

## Summary

Monitor clipboard changes, detecting copied content, paste events, and clipboard history access, playing sounds for clipboard events.

## Motivation

- Clipboard change feedback
- Sensitive content alerts
- Paste confirmation
- Clipboard history access

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Clipboard Events

| Event | Description | Example |
|-------|-------------|---------|
| Clipboard Copy | New content copied | Text/image copied |
| Clipboard Paste | Content pasted | Ctrl+V pressed |
| Clipboard Clear | Clipboard cleared | Auto-clear triggered |
| Sensitive Copied | Sensitive content copied | Password copied |
| Clipboard History | History accessed | History menu opened |

### Configuration

```go
type ClipboardMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    SoundOnCopy       bool              `json:"sound_on_copy"`
    SoundOnPaste      bool              `json:"sound_on_paste"`
    WatchTypes        []string          `json:"watch_types"` // "text", "image", "file"
    SensitivePatterns []string          `json:"sensitive_patterns"` // Regex patterns
    MaxHistorySize    int               `json:"max_history_size"` // 50 default
    Sounds            map[string]string `json:"sounds"`
}

type ClipboardEvent struct {
    EventType  string // "copy", "paste", "clear"
    ContentType string // "text", "image", "file"
    ContentLen  int
    IsSensitive bool
}
```

### Commands

```bash
/ccbell:clipboard status          # Show clipboard status
/ccbell:clipboard copy on         # Enable copy sounds
/ccbell:clipboard paste on        # Enable paste sounds
/ccbell:clipboard sound copy <sound>
/ccbell:clipboard sound sensitive <sound>
/ccbell:clipboard test            # Test clipboard sounds
```

### Output

```
$ ccbell:clipboard status

=== Sound Event Clipboard Monitor ===

Status: Enabled
Copy Sounds: Yes
Paste Sounds: Yes

Current Clipboard:
  Type: Text
  Length: 145 characters
  Content Preview: "Hello, world!"
  Sensitive: No

Clipboard History:
  Items: 12 stored
  Last Copy: 2 min ago

Recent Events:
  [1] Text copied (2 min ago)
  [2] Image pasted (15 min ago)
  [3] Password copied (1 hour ago) - Sensitive
  [4] Clipboard cleared (2 hours ago)

Sound Settings:
  Copy: bundled:stop
  Paste: bundled:stop
  Sensitive: bundled:stop

[Configure] [Test All] [Clear History]
```

---

## Audio Player Compatibility

Clipboard monitoring doesn't play sounds directly:
- Monitoring feature using clipboard APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Clipboard Monitor

```go
type ClipboardMonitor struct {
    config        *ClipboardMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    lastContent   string
    history       []ClipboardEvent
}

func (m *ClipboardMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.history = make([]ClipboardEvent, 0)
    go m.monitor()
}

func (m *ClipboardMonitor) monitor() {
    ticker := time.NewTicker(500 * time.Millisecond)
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

func (m *ClipboardMonitor) checkClipboard() {
    content := m.getClipboardContent()
    if content == "" {
        return
    }

    if content != m.lastContent {
        m.onClipboardChange(content)
        m.lastContent = content
    }
}

func (m *ClipboardMonitor) getClipboardContent() string {
    if runtime.GOOS == "darwin" {
        return m.getMacOSClipboard()
    }
    if runtime.GOOS == "linux" {
        return m.getLinuxClipboard()
    }
    return ""
}

func (m *ClipboardMonitor) getMacOSClipboard() string {
    cmd := exec.Command("pbpaste")
    output, err := cmd.Output()
    if err != nil {
        return ""
    }
    return string(output)
}

func (m *ClipboardMonitor) getLinuxClipboard() string {
    // Try xclip first
    cmd := exec.Command("xclip", "-selection", "clipboard", "-o")
    output, err := cmd.Output()
    if err != nil {
        // Try xsel
        cmd = exec.Command("xsel", "--clipboard", "--output")
        output, err = cmd.Output()
        if err != nil {
            return ""
        }
    }
    return string(output)
}

func (m *ClipboardMonitor) onClipboardChange(content string) {
    event := ClipboardEvent{
        EventType:   "copy",
        ContentLen:  len(content),
        IsSensitive: m.isSensitive(content),
    }

    // Determine content type
    if m.isImageContent() {
        event.ContentType = "image"
    } else if m.isFileContent(content) {
        event.ContentType = "file"
    } else {
        event.ContentType = "text"
    }

    // Add to history
    m.addToHistory(event)

    // Play sound
    if event.IsSensitive {
        m.onSensitiveContent()
    } else if m.config.SoundOnCopy {
        m.onCopy(event)
    }
}

func (m *ClipboardMonitor) isSensitive(content string) bool {
    for _, pattern := range m.config.SensitivePatterns {
        matched, _ := regexp.MatchString(pattern, content)
        if matched {
            return true
        }
    }
    return false
}

func (m *ClipboardMonitor) isImageContent() bool {
    if runtime.GOOS == "darwin" {
        cmd := exec.Command("osascript", "-e",
            "if clipboard info as text contains \"PNG\" or clipboard info as text contains \"JPEG\" then return true else return false")
        output, _ := cmd.Output()
        return strings.Contains(string(output), "true")
    }
    if runtime.GOOS == "linux" {
        cmd := exec.Command("xclip", "-selection", "clipboard", "-t", "image/png", "-o")
        err := cmd.Run()
        return err == nil
    }
    return false
}

func (m *ClipboardMonitor) isFileContent(content string) bool {
    // Check if content looks like a file path
    return strings.HasPrefix(content, "/") || strings.HasPrefix(content, "./")
}

func (m *ClipboardMonitor) addToHistory(event ClipboardEvent) {
    m.history = append([]ClipboardEvent{event}, m.history...)
    if len(m.history) > m.config.MaxHistorySize {
        m.history = m.history[:m.config.MaxHistorySize]
    }
}

func (m *ClipboardMonitor) onCopy(event ClipboardEvent) {
    sound := m.config.Sounds["copy"]
    if event.ContentType != "text" {
        sound = m.config.Sounds[event.ContentType+"_copy"]
    }
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *ClipboardMonitor) onSensitiveContent() {
    sound := m.config.Sounds["sensitive"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *ClipboardMonitor) onPaste(event ClipboardEvent) {
    if !m.config.SoundOnPaste {
        return
    }
    sound := m.config.Sounds["paste"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *ClipboardMonitor) onClear() {
    sound := m.config.Sounds["clear"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| pbpaste | System Tool | Free | macOS clipboard |
| xclip | APT | Free | Linux clipboard |
| xsel | APT | Free | Linux clipboard |
| osascript | System Tool | Free | macOS automation |

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
| macOS | Supported | Uses pbpaste/osascript |
| Linux | Supported | Uses xclip or xsel |
| Windows | Not Supported | ccbell only supports macOS/Linux |
