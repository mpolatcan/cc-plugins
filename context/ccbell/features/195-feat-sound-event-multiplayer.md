# Feature: Sound Event Multiplayer

Shared configuration synchronization.

## Summary

Synchronize configurations across multiple machines or users.

## Motivation

- Team consistency
- Cross-device sync
- Shared configurations

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | High |
| **Estimated Effort** | 5-7 days |

---

## Technical Feasibility

### Sync Types

| Type | Description | Example |
|-------|-------------|---------|
| Local | Sync on same machine | User across devices |
| Network | Local network sync | Team sync |
| Cloud | Cloud sync | Remote team |
| File | File-based sync | Git repository |

### Configuration

```go
type MultiplayerConfig struct {
    Enabled       bool              `json:"enabled"`
    Mode          string            `json:"mode"` // "local", "network", "cloud", "file"
    SyncInterval  int               `json:"sync_interval_minutes"` // 5 default
    Conflicts     string            `json:"conflict_resolution"` // "local", "remote", "ask"
    Peers         []Peer            `json:"peers"`
    LastSync      time.Time         `json:"last_sync"`
}

type Peer struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Address     string   `json:"address"` // URL or path
    Type        string   `json:"type"` // "server", "client", "git"
    AuthToken   string   `json:"auth_token,omitempty"`
    LastSeen    time.Time `json:"last_seen"`
    Status      string   `json:"status"` // "online", "offline", "syncing"
}

type SyncState struct {
    ConfigHash   string    `json:"config_hash"`
    SoundsHash   string    `json:"sounds_hash"`
    LastSync     time.Time `json:"last_sync"`
    Version      int       `json:"version"`
}
```

### Commands

```bash
/ccbell:multiplayer status          # Show sync status
/ccbell:multiplayer mode local      # Set sync mode
/ccbell:multiplayer add peer "Team" --address https://sync.example.com
/ccbell:multiplayer sync            # Force sync now
/ccbell:multiplayer sync dry-run    # Preview sync changes
/ccbell:multiplayer remove peer <id>
/ccbell:multiplayer conflict local  # Resolve conflicts
/ccbell:multiplayer interval 10     # Set sync interval
```

### Output

```
$ ccbell:multiplayer status

=== Sound Event Multiplayer ===

Status: Enabled
Mode: Network
Sync Interval: 5 min
Last Sync: 2 min ago
Conflicts: 0

Peers: 3

[1] Team Server
    Address: https://sync.example.com
    Status: Online
    Last Seen: 1 min ago
    Version: 45
    [Edit] [Remove] [Sync]

[2] Desktop
    Address: 192.168.1.100:8080
    Status: Online
    Last Seen: 2 min ago
    Version: 44
    [Edit] [Remove] [Sync]

[3] Laptop
    Address: /Users/shared/ccbell-sync
    Status: Offline
    Last Seen: 2 hours ago
    Version: 40
    [Edit] [Remove] [Sync]

[Configure] [Add Peer] [Sync Now]
```

---

## Audio Player Compatibility

Multiplayer doesn't play sounds:
- Sync feature
- No player changes required

---

## Implementation

### Sync Manager

```go
type SyncManager struct {
    config   *MultiplayerConfig
    cfg      *config.Config
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
}

func (m *SyncManager) Start() {
    m.running = true
    m.stopCh = make(chan struct{})

    go m.syncLoop()
}

func (m *SyncManager) syncLoop() {
    ticker := time.NewTicker(time.Duration(m.config.SyncInterval) * time.Minute)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.syncAll()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SyncManager) syncAll() {
    for _, peer := range m.config.Peers {
        if err := m.syncWithPeer(peer); err != nil {
            peer.Status = "offline"
        } else {
            peer.Status = "online"
            peer.LastSeen = time.Now()
        }
    }

    m.config.LastSync = time.Now()
}

func (m *SyncManager) syncWithPeer(peer *Peer) error {
    peer.Status = "syncing"

    // Get remote state
    remoteState, err := m.getRemoteState(peer)
    if err != nil {
        return err
    }

    // Get local state
    localState := m.getLocalState()

    // Compare versions
    if remoteState.Version > localState.Version {
        return m.pullFromPeer(peer, remoteState)
    } else if localState.Version > remoteState.Version {
        return m.pushToPeer(peer, localState)
    }

    // Same version, compare hashes
    if remoteState.ConfigHash != localState.ConfigHash {
        return m.resolveConflict(peer)
    }

    return nil
}

func (m *SyncManager) pushToPeer(peer *Peer, state *SyncState) error {
    // Export config
    data, err := m.exportConfig()
    if err != nil {
        return err
    }

    switch peer.Type {
    case "server":
        return m.pushToServer(peer, data, state)
    case "git":
        return m.pushToGit(peer, data)
    case "client":
        return m.pushToClient(peer, data)
    }

    return nil
}

func (m *SyncManager) resolveConflict(peer *Peer) error {
    switch m.config.Conflicts {
    case "local":
        return m.pushToPeer(peer, m.getLocalState())
    case "remote":
        return m.pullFromPeer(peer, nil)
    case "ask":
        // Prompt user for resolution
        return m.promptConflictResolution(peer)
    }

    return nil
}

func (m *SyncManager) pushToServer(peer *Peer, data []byte, state *SyncState) error {
    url := fmt.Sprintf("%s/api/sync", peer.Address)

    req, err := http.NewRequest("POST", url, bytes.NewReader(data))
    if err != nil {
        return err
    }

    if peer.AuthToken != "" {
        req.Header.Set("Authorization", "Bearer "+peer.AuthToken)
    }

    resp, err := http.DefaultClient.Do(req)
    if err != nil {
        return err
    }
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        return fmt.Errorf("sync failed: %d", resp.StatusCode)
    }

    return nil
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| http | Go Stdlib | Free | Network sync |
| git | System Tool | Free | File-based sync |
| crypto | Go Stdlib | Free | Hash generation |

---

## References

### ccbell Implementation Research

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config serialization
- [Export feature](features/189-feat-sound-event-export.md) - Export for sync
- [Import feature](features/190-feat-sound-event-import.md) - Import for sync

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
