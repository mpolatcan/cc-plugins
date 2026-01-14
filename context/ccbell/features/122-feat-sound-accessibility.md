# Feature: Sound Accessibility

Accessibility features for sound management.

## Summary

Accessibility support for users with hearing impairments or other needs.

## Motivation

- Accessibility compliance
- Visual alternatives
- Customizable feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Accessibility Features

| Feature | Description | Use Case |
|---------|-------------|----------|
| Visual Alert | Flash screen on sound | Hearing impaired |
| Caption | Show sound name | Identify sounds |
| Vibration | Vibrate on sound | Haptic feedback |
| LED | LED indicator | Silent notification |

### Configuration

```go
type AccessibilityConfig struct {
    Enabled         bool              `json:"enabled"`
    VisualAlert     VisualAlertConfig `json:"visual_alert"`
    Caption         CaptionConfig     `json:"caption"`
    Vibration       bool              `json:"vibration"`
    LEDIndicator    bool              `json:"led_indicator"`
    HighContrast    bool              `json:"high_contrast"`
}

type VisualAlertConfig struct {
    Enabled     bool    `json:"enabled"`
    FlashScreen bool    `json:"flash_screen"`
    FlashColor  string  `json:"flash_color"` // hex color
    DurationMs  int     `json:"duration_ms"`
}

type CaptionConfig struct {
    Enabled     bool   `json:"enabled"`
    Position    string `json:"position"` // top, bottom, overlay
    Duration    int    `json:"duration_sec"`
    FontSize    int    `json:"font_size"`
}
```

### Commands

```bash
/ccbell:a11y enable                  # Enable accessibility
/ccbell:a11y disable                 # Disable accessibility
/ccbell:a11y visual enable           # Enable visual alerts
/ccbell:a11y visual flash-color #FF0000
/ccbell:a11y caption enable          # Enable captions
/ccbell:a11y caption position bottom
/ccbell:a11y caption duration 3      # 3 seconds
/ccbell:a11y test                    # Test accessibility features
```

### Output

```
$ ccbell:a11y status

=== Accessibility Settings ===

Status: Enabled

[✓] Visual Alerts
    Flash Screen: Yes
    Color: #FF0000 (Red)
    Duration: 500ms

[✓] Captions
    Position: Bottom
    Duration: 3s
    Font Size: 14px

[ ] Vibration (not available)

[ ] LED Indicator (not available)

[Configure] [Test] [Disable]
```

---

## Audio Player Compatibility

Accessibility features work alongside audio player:
- Visual feedback during/after playback
- No player changes required
- Terminal output for captions

---

## Implementation

### Visual Alert

```go
func (a *AccessibilityManager) flashScreen(color string, durationMs int) error {
    // For terminal: flash background
    fmt.Printf("\033[48;2;%s;1m", color) // Set background color
    fmt.Printf("\033[2J")               // Clear screen
    time.Sleep(time.Duration(durationMs) * time.Millisecond)
    fmt.Printf("\033[0m")               // Reset
    return nil
}
```

### Caption Display

```go
func (a *AccessibilityManager) showCaption(soundName string) {
    if !a.config.Caption.Enabled {
        return
    }

    position := a.config.Caption.Position
    duration := time.Duration(a.config.Caption.Duration) * time.Second

    switch position {
    case "bottom":
        fmt.Printf("\033[%d;0H", 24) // Move to bottom
        fmt.Printf("\033[7m") // Reverse video
        fmt.Printf("🔔 %s", soundName)
        fmt.Printf("\033[0m")

        time.Sleep(duration)

        // Clear
        fmt.Printf("\033[%d;0H", 24)
        fmt.Printf("\033[2K")
    case "overlay":
        fmt.Printf("\033[2;0H")
        fmt.Printf("\033[7m")
        fmt.Printf("🔔 %s", soundName)
        fmt.Printf("\033[0m")
    }
}
```

### macOS Accessibility

```go
func (a *AccessibilityManager) flashMacOS(color string) error {
    // Use AppleScript for visual notification
    script := fmt.Sprintf(`
tell application "System Events"
    keystroke " " using {command down, option down}
end tell
    `)

    return exec.Command("osascript", "-e", script).Run()
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go (terminal) |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Accessibility hook

### Research Sources

- [WCAG guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [Terminal ANSI codes](https://en.wikipedia.org/wiki/ANSI_escape_code)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Terminal + AppleScript |
| Linux | ✅ Supported | Terminal + notify-send |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
