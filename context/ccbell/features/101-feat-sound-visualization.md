# Feature: Sound Visualization

Visual indicators for playing sounds.

## Summary

Display visual feedback when sounds are playing.

## Motivation

- Visual confirmation
- Debug playback issues
- Accessibility

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Visualization Types

| Type | Description | Use Case |
|------|-------------|----------|
| Waveform | Real-time waveform | Visual feedback |
| Bar | Level meter bars | Volume indicator |
| Icon | System tray icon | Subtle notification |
| Terminal | ANSI animation | CLI feedback |

### Configuration

```go
type VisualizationConfig struct {
    Enabled     bool    `json:"enabled"`
    Type        string  `json:"type"`        // "waveform", "bar", "icon", "terminal"
    Position    string  `json:"position"`    // "top-right", "bottom", "tray"
    Color       string  `json:"color"`       // ANSI color or hex
    Duration    int     `json:"duration"`    // seconds to show
    AutoHide    bool    `json:"auto_hide"`   // hide after play
    Size        int     `json:"size"`        // width in chars
}

type VisualState struct {
    IsPlaying   bool      `json:"is_playing"`
    SoundName   string    `json:"sound_name"`
    Volume      float64   `json:"volume"`
    StartTime   time.Time `json:"start_time"`
    Waveform    []float64 `json:"waveform"`
}
```

### Commands

```bash
/ccbell:vis enable                  # Enable visualization
/ccbell:vis disable                 # Disable visualization
/ccbell:vis set type waveform       # Set visual type
/ccbell:vis set type bar --color green
/ccbell:vis set duration 3          # Show for 3 seconds
/ccbell:vis test                    # Test visualization
/ccbell:vis preview waveform        # Preview animation
```

### Output

```
$ ccbell:vis test

=== Sound Visualization ===

Status: Enabled
Type: Waveform
Duration: 2s

[██████████▓▓▓▓▓▓▓▓░░░░░░] Playing: bundled:stop (0.5s)
[███████████████▓▓▓▓░░░░] Volume: 50%
[█████████████████████░] ▸

[██████████▓▓▓▓▓▓░░░░░░░] 0.5s remaining
[█████████████████████░░] ▸

Animation preview complete
[Configure] [Test Again] [Close]
```

---

## Audio Player Compatibility

Visualization doesn't play sounds:
- Display feature
- No player changes required
- Terminal ANSI for CLI

---

## Implementation

### Terminal Waveform

```go
func (v *Visualizer) renderWaveform(state *VisualState) string {
    width := v.config.Size
    bars := make([]string, width)

    // Generate simulated waveform
    samples := 32
    for i := 0; i < width; i++ {
        sampleIdx := (i * samples) / width
        amplitude := state.Waveform[sampleIdx%len(state.Waveform)]

        filled := int(amplitude * float64(width) * 0.8)
        bar := strings.Repeat("█", filled) + strings.Repeat("░", width-filled)
        bars[i] = bar
    }

    return fmt.Sprintf("[%s]", strings.Join(bars, "]["))
}
```

### ANSI Bar Meter

```go
func (v *Visualizer) renderBar(volume float64) string {
    width := v.config.Size
    filled := int(volume * float64(width))

    blocks := []string{"░", "▒", "▓", "█"}
    blockCount := 4

    result := "["
    for i := 0; i < width; i++ {
        if i < filled {
            result += blocks[blockCount-1]
        } else {
            result += blocks[0]
        }
    }
    result += fmt.Sprintf("] %.0f%%", volume*100)

    return result
}
```

### macOS Notification

```go
func (v *Visualizer) showNotification(soundName string) error {
    // Use osascript for macOS notification
    script := fmt.Sprintf(`
tell application "System Events"
    display notification "Playing: %s" with title "CCBell"
end tell
    `, soundName)

    cmd := exec.Command("osascript", "-e", script)
    return cmd.Run()
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go (terminal output) |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Playback hook

### Research Sources

- [ANSI escape codes](https://en.wikipedia.org/wiki/ANSI_escape_code)
- [Go terminal packages](https://pkg.go.dev/golang.org/x/term)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Terminal + notifications |
| Linux | ✅ Supported | Terminal + notifications |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
