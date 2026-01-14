# Feature: Sound Library Sync

Sync sound library across multiple machines.

## Summary

Synchronize sounds and configurations between devices.

## Motivation

- Consistent sounds across devices
- Backup sound library
- Share with other users

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Sync Options

| Method | Description | Use Case |
|--------|-------------|----------|
| Local sync | Sync to local directory | Backup |
| Cloud sync | Sync to cloud storage | Cross-device |
| Git sync | Sync via git repository | Version control |
| HTTP sync | Sync from HTTP server | Central server |

### Configuration

```go
type SyncConfig struct {
    Enabled       bool          `json:"enabled"`
    Method        string        `json:"method"` // "local", "cloud", "git", "http"
    Target        string        `json:"target"` // path, URL, repo
    Frequency     string        `json:"frequency"` // "manual", "auto", "scheduled"
    IncludeConfig bool          `json:"include_config"`
    IncludeSounds bool          `json:"include_sounds"`
    IncludeState  bool          `json:"include_state"`
    ConflictResolution string   `json:"conflict_resolution"` // "local", "remote", "newest"
    Auth          *AuthConfig   `json:"auth,omitempty"`
}

type SyncState struct {
    LastSync      time.Time `json:"last_sync"`
    LastSuccessful time.Time `json:"last_successful"`
    SyncCount     int       `json:"sync_count"`
    FailedCount   int       `json:"failed_count"`
    ChangesPending bool     `json:"changes_pending"`
}
```

### Commands

```bash
/ccbell:sync status              # Show sync status
/ccbell:sync now                 # Sync now
/ccbell:sync local ~/Dropbox/ccbell
/ccbell:sync git https://github.com/user/ccbell-sounds
/ccbell:sync http https://sync.example.com/ccbell
/ccbell:sync schedule hourly     # Hourly sync
/ccbell:sync schedule daily      # Daily sync
/ccbell:sync conflicts           # Show conflicts
/ccbell:sync resolve --use remote # Resolve conflicts
/ccbell:sync history             # Show sync history
```

### Output

```
$ ccbell:sync status

=== Sound Library Sync ===

Method: Git
Target: https://github.com/user/ccbell-sounds
Status: Connected

Last Sync: Jan 14, 2024 10:30 AM
Status: Success (23 files, 15.2 MB)

Pending Changes:
  + custom:new-bell.aiff
  ~ config (modified locally)

Sync Schedule: Manual
Conflicts: 2

[Sync Now] [Conflicts] [Settings] [History]
```

---

## Audio Player Compatibility

Sync doesn't play sounds:
- File transfer operations
- No player changes required

---

## Implementation

### Git Sync

```go
type GitSync struct {
    repoDir   string
    remoteURL string
}

func (g *GitSync) Sync() (*SyncResult, error) {
    // Pull latest changes
    if err := g.gitPull(); err != nil {
        return nil, err
    }

    // Stage local changes
    if err := g.gitAdd(); err != nil {
        return nil, err
    }

    // Commit local changes
    if err := g.gitCommit(); err != nil {
        return nil, err
    }

    // Push to remote
    if err := g.gitPush(); err != nil {
        return nil, err
    }

    return &SyncResult{
        FilesPulled: g.countPulled(),
        FilesPushed: g.countPushed(),
        Timestamp:   time.Now(),
    }, nil
}
```

### Conflict Detection

```go
func (s *SyncManager) detectConflicts() []Conflict {
    conflicts := []Conflict{}

    for _, file := range s.getTrackedFiles() {
        localHash := hashFile(file)
        remoteHash := s.getRemoteHash(file)

        if localHash != remoteHash {
            conflicts = append(conflicts, Conflict{
                File:     file,
                LocalMD5: localHash,
                RemoteMD5: remoteHash,
            })
        }
    }

    return conflicts
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| git | External tool | Free | For git sync |
| curl | External tool | Free | For HTTP sync |

---

## References

### ccbell Implementation Research

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config sync
- [Sound paths](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound resolution

### Research Sources

- [Go git library](https://github.com/go-git/go-git)
- [rsync protocol](https://rsync.samba.org/)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via git/curl |
| Linux | ✅ Supported | Via git/curl |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
