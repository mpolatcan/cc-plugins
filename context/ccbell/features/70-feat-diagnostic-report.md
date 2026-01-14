# Feature: Diagnostic Report Generation

Generate comprehensive diagnostic reports for troubleshooting.

## Summary

Create detailed reports combining all diagnostic information for support or debugging.

## Motivation

- Share troubleshooting info easily
- Comprehensive system overview
- Support request assistance

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Report Sections

| Section | Content |
|---------|---------|
| System | OS, architecture, shell |
| ccbell | Version, installation path |
| Audio | Available players, device info |
| Config | Full config (sanitized) |
| State | Cooldowns, counters, history |
| Sounds | Bundled, custom, packs |
| Logs | Recent log entries |
| Hooks | Hook configuration |

### Implementation

```go
type DiagnosticReport struct {
    GeneratedAt   time.Time    `json:"generated_at"`
    Version       string       `json:"version"`
    System        SystemInfo   `json:"system"`
    Audio         AudioInfo    `json:"audio"`
    Config        *Config      `json:"config"`
    State         *State       `json:"state"`
    SoundStatus   SoundStatus  `json:"sound_status"`
    RecentLogs    []LogEntry   `json:"recent_logs,omitempty"`
}

type SystemInfo struct {
    OS           string `json:"os"`
    Architecture string `json:"architecture"`
    Shell        string `json:"shell"`
    HomeDir      string `json:"home_dir"`
    User         string `json:"user"`
}

type AudioInfo struct {
    Platform      string   `json:"platform"`
    AvailablePlayers []string `json:"available_players"`
    DefaultPlayer string   `json:"default_player"`
    VolumeControl bool     `json:"volume_control"`
}
```

### Commands

```bash
/ccbell:report generate           # Generate report
/ccbell:report generate --json    # JSON format
/ccbell:report generate --include-logs  # Include recent logs
/ccbell:report upload             # Upload to pastebin (optional)
ccbell --report > report.txt     # Full diagnostic
```

### Output Example

```
=== ccbell Diagnostic Report ===
Generated: 2026-01-14 10:32:05
Version: 0.2.30

=== System ===
OS: Darwin 23.2.0 (macOS)
Architecture: arm64
Shell: /bin/zsh
User: username

=== Audio ===
Platform: macOS
Available: afplay
Default: afplay
Volume Control: Yes

=== Configuration ===
Enabled: true
Active Profile: default
Events: 4 configured
Quiet Hours: 22:00-07:00

=== Sound Status ===
Bundled: 4/4 present
Custom: 12 sounds
Packs: 2 installed

=== State ===
Cooldowns: 0 active
Event Counters: 4 events tracked

=== Report saved to: /Users/me/.claude/ccbell/report.txt ===
```

### Sanitization

```go
func sanitizeConfig(cfg *Config) *Config {
    // Remove sensitive data
    sanitized := *cfg

    // Keep structure but remove values
    // ... sanitization logic

    return &sanitized
}
```

---

## Audio Player Compatibility

Diagnostic report doesn't interact with audio playback:
- Reads system and config information
- No player changes required
- Uses existing player detection

---

## Implementation

### Report Generation

```go
func (c *CCBell) GenerateReport(includeLogs bool) (*DiagnosticReport, error) {
    report := &DiagnosticReport{
        GeneratedAt: time.Now(),
        Version:     version,
        System:      c.getSystemInfo(),
        Audio:       c.getAudioInfo(),
    }

    cfg, _, _ := config.Load(homeDir)
    report.Config = sanitizeConfig(cfg)

    state, _ := state.Load(homeDir)
    report.State = state

    report.SoundStatus = c.getSoundStatus()

    if includeLogs {
        report.RecentLogs = c.getRecentLogs(50)
    }

    return report, nil
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

- [Version info](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Version detection
- [Audio detection](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L217-L235) - Player detection
- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config reading

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Full diagnostics |
| Linux | ✅ Supported | Full diagnostics |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
