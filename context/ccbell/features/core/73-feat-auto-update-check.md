# Feature: Auto-Update Check

Check for new ccbell versions automatically.

## Summary

Periodically check for new ccbell releases and notify users.

## Motivation

- Stay up to date
- Security updates
- New features awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Version Check

```go
type UpdateCheck struct {
    Enabled       bool   `json:"enabled"`
    CheckInterval int    `json:"check_interval_hours"` // 24, 168 (weekly)
    LastCheck     time.Time `json:"last_check"`
    LastVersion   string `json:"last_version"`
    NotifyOnStart bool   `json:"notify_on_start"`
}

func checkForUpdate() (*UpdateInfo, error) {
    resp, err := http.Get("https://api.github.com/repos/mpolatcan/ccbell/releases/latest")
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    var release struct {
        TagName string `json:"tag_name"`
        HTMLURL string `json:"html_url"`
        Body    string `json:"body"`
    }

    json.NewDecoder(resp.Body).Decode(&release)

    return &UpdateInfo{
        Version:   release.TagName,
        URL:       release.HTMLURL,
        Changelog: release.Body,
    }, nil
}
```

### Configuration

```json
{
  "update_check": {
    "enabled": true,
    "check_interval_hours": 24,
    "notify_on_start": true,
    "channel": "latest"  // "latest", "stable"
  }
}
```

### Commands

```bash
/ccbell:update check              # Check now
/ccbell:update check --force      # Force refresh
/ccbell:update status             # Show update status
/ccbell:update disable            # Disable auto-check
/ccbell:update settings           # Configure settings
```

### Output

```
$ ccbell:update check

Checking for updates...
Current version: 0.2.30
Latest version: 0.2.31

Update available!
Changelog:
- Fix audio player detection on Linux
- Add new bundled sounds
- Performance improvements

Update now: https://github.com/mpolatcan/ccbell/releases/tag/v0.2.31

$ ccbell:update status

=== Update Check Status ===

Auto-check: Enabled
Last check: Jan 13, 10:32
Next check: Jan 14, 10:32
Channel: latest
Current version: 0.2.30 (up to date)
```

### Update Notification

```
$ ccbell stop
ccbell v0.2.30 - Playing notification
ℹ Update available: v0.2.31 (checked Jan 14, 2026)
Run 'ccbell:update check' for details
```

---

## Audio Player Compatibility

Update check doesn't interact with audio playback:
- HTTP version check
- No player changes required
- Purely informational

---

## Implementation

### Scheduled Check

```go
func (c *CCBell) startUpdateChecker() {
    if c.updateConfig == nil || !c.updateConfig.Enabled {
        return
    }

    interval := time.Duration(c.updateConfig.CheckInterval) * time.Hour

    go func() {
        for range time.Tick(interval) {
            c.checkForUpdate()
        }
    }()
}
```

### Notification

```go
func (c *CCBell) notifyIfUpdateAvailable() {
    info, _ := c.checkForUpdate()
    if info != nil && info.Version != currentVersion {
        fmt.Printf("\nℹ Update available: %s\n", info.Version)
        fmt.Printf("Run 'ccbell:update check' for details\n")
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| GitHub API | External | Free | No auth required for public repos |

---

## References

### Research Sources

- [GitHub Releases API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)
- [Semantic versioning](https://semver.org/)

### ccbell Implementation Research

- [Version info](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Version detection
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Update config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | HTTP check |
| Linux | ✅ Supported | HTTP check |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
