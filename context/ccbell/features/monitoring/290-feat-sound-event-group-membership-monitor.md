# Feature: Sound Event Group Membership Monitor

Play sounds for group membership changes.

## Summary

Monitor group membership additions and removals, playing sounds for group configuration changes.

## Motivation

- Security group alerts
- Permission change awareness
- Group policy enforcement
- Audit trail feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Group Membership Events

| Event | Description | Example |
|-------|-------------|---------|
| User Added | Member added to group | user -> sudo |
| User Removed | Member removed | user -> sudo |
| Group Created | New group added | newgroup |
| Group Deleted | Group removed | oldgroup |

### Configuration

```go
type GroupMembershipMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchGroups      []string          `json:"watch_groups"` // "sudo", "admin", "wheel"
    WatchUsers       []string          `json:"watch_users"`
    SoundOnAdd       bool              `json:"sound_on_add"]
    SoundOnRemove    bool              `json:"sound_on_remove"]
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 60 default
}

type GroupMembershipEvent struct {
    GroupName  string
    UserName   string
    Action     string // "add", "remove", "create", "delete"
    IsAdmin    bool   // admin/sudo group
    Timestamp  time.Time
}
```

### Commands

```bash
/ccbell:group status                 # Show group status
/ccbell:group add sudo               # Add group to watch
/ccbell:group remove sudo
/ccbell:group sound add <sound>
/ccbell:group sound remove <sound>
/ccbell:group test                   # Test group sounds
```

### Output

```
$ ccbell:group status

=== Sound Event Group Membership Monitor ===

Status: Enabled
Add Sounds: Yes
Remove Sounds: Yes

Watched Groups: 3

[1] sudo (members: user, admin)
    Status: 2 members
    Sound: bundled:stop

[2] admin (members: admin)
    Status: 1 member
    Sound: bundled:stop

[3] wheel (members: root)
    Status: 1 member
    Sound: bundled:stop

Recent Events:
  [1] admin: User Removed (1 hour ago)
       Removed: oldadmin
  [2] sudo: User Added (2 hours ago)
       Added: newuser
  [3] wheel: No changes (1 day ago)

Membership Changes Today:
  - 1 user added to sudo
  - 1 user removed from admin

Sound Settings:
  Add: bundled:stop
  Remove: bundled:stop
  Create: bundled:stop

[Configure] [Add Group] [Test All]
```

---

## Audio Player Compatibility

Group membership monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Group Membership Monitor

```go
type GroupMembershipMonitor struct {
    config          *GroupMembershipMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    groupState      map[string][]string
    lastChangeTime  time.Time
}

func (m *GroupMembershipMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.groupState = make(map[string][]string)
    go m.monitor()
}

func (m *GroupMembershipMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotGroups()

    for {
        select {
        case <-ticker.C:
            m.checkGroupChanges()
        case <-m.stopCh:
            return
        }
    }
}

func (m *GroupMembershipMonitor) snapshotGroups() {
    // Get current group memberships
    for _, group := range m.config.WatchGroups {
        members := m.getGroupMembers(group)
        m.groupState[group] = members
    }
}

func (m *GroupMembershipMonitor) getGroupMembers(groupName string) []string {
    var members []string

    cmd := exec.Command("dscl", ".", "-read", "/Groups/"+groupName, "GroupMembership")
    output, err := cmd.Output()

    if err == nil {
        // macOS output
        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            line = strings.TrimSpace(line)
            if line != "" && line != "GroupMembership:" {
                members = append(members, line)
            }
        }
    } else {
        // Try using getent on Linux
        cmd = exec.Command("getent", "group", groupName)
        output, err = cmd.Output()
        if err == nil {
            parts := strings.SplitN(string(output), ":", 4)
            if len(parts) >= 4 {
                membersStr := parts[3]
                if membersStr != "" {
                    members = strings.Split(strings.TrimSuffix(membersStr, "\n"), ",")
                }
            }
        }
    }

    return members
}

func (m *GroupMembershipMonitor) checkGroupChanges() {
    for _, group := range m.config.WatchGroups {
        currentMembers := m.getGroupMembers(group)
        lastMembers := m.groupState[group]

        added := m.findAddedItems(lastMembers, currentMembers)
        removed := m.findAddedItems(currentMembers, lastMembers)

        for _, user := range added {
            m.onUserAddedToGroup(group, user)
        }

        for _, user := range removed {
            m.onUserRemovedFromGroup(group, user)
        }

        m.groupState[group] = currentMembers
    }
}

func (m *GroupMembershipMonitor) findAddedItems(oldSlice, newSlice []string) []string {
    added := []string{}
    for _, item := range newSlice {
        found := false
        for _, old := range oldSlice {
            if item == old {
                found = true
                break
            }
        }
        if !found {
            added = append(added, item)
        }
    }
    return added
}

func (m *GroupMembershipMonitor) onUserAddedToGroup(group string, user string) {
    // Check if user should be watched
    if len(m.config.WatchUsers) > 0 {
        found := false
        for _, watchUser := range m.config.WatchUsers {
            if user == watchUser {
                found = true
                break
            }
        }
        if !found {
            return
        }
    }

    if !m.config.SoundOnAdd {
        return
    }

    // Check for admin/sudo groups (high priority)
    isAdmin := (group == "sudo" || group == "admin" || group == "wheel")

    event := &GroupMembershipEvent{
        GroupName: group,
        UserName:  user,
        Action:    "add",
        IsAdmin:   isAdmin,
    }

    if isAdmin {
        sound := m.config.Sounds["admin_add"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    } else {
        sound := m.config.Sounds["add"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *GroupMembershipMonitor) onUserRemovedFromGroup(group string, user string) {
    // Check if user should be watched
    if len(m.config.WatchUsers) > 0 {
        found := false
        for _, watchUser := range m.config.WatchUsers {
            if user == watchUser {
                found = true
                break
            }
        }
        if !found {
            return
        }
    }

    if !m.config.SoundOnRemove {
        return
    }

    isAdmin := (group == "sudo" || group == "admin" || group == "wheel")

    if isAdmin {
        sound := m.config.Sounds["admin_remove"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    } else {
        sound := m.config.Sounds["remove"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| dscl | System Tool | Free | macOS directory service |
| getent | System Tool | Free | Linux group lookup |

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
| macOS | Supported | Uses dscl |
| Linux | Supported | Uses getent |
| Windows | Not Supported | ccbell only supports macOS/Linux |
