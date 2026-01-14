# Feature: Sound Event Grouping

Group events and control them together.

## Summary

Create groups of events that can be enabled, disabled, or configured together.

## Motivation

- Batch control
- Category management
- Context-based groups

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Group Types

| Type | Description | Example |
|------|-------------|---------|
| By Category | Similar events together | All prompts |
| By Priority | Priority-based grouping | High, medium, low |
| By Time | Time-based grouping | Work, personal |
| Custom | User-defined groups | Custom sets |

### Configuration

```go
type GroupConfig struct {
    Enabled     bool              `json:"enabled"`
    Groups      map[string]*EventGroup `json:"groups"`
}

type EventGroup struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Events      []string `json:"events"` // Event types in group
    Enabled     bool     `json:"enabled"`
    Volume      *float64 `json:"volume,omitempty"` // Group volume override
    Cooldown    *int     `json:"cooldown,omitempty"` // Group cooldown override
    Priority    int      `json:"priority"` // 0-100, higher = more important
    Exclusive   bool     `json:"exclusive"` // Only one event from group at a time
}
```

### Commands

```bash
/ccbell:group list                  # List groups
/ccbell:group create "Prompts" --events permission_prompt,idle_prompt
/ccbell:group create "High Priority" --events stop,subagent --priority 100
/ccbell:group enable <id>           # Enable group
/ccbell:group disable <id>          # Disable group
/ccbell:group volume <id> 0.8       # Set group volume
/ccbell:group delete <id>           # Remove group
/ccbell:group status                # Show all groups status
```

### Output

```
$ ccbell:group list

=== Sound Event Groups ===

Groups: 3

[1] Prompts
    Events: permission_prompt, idle_prompt
    Status: Enabled
    Volume: 0.7 (override)
    [Edit] [Disable] [Delete]

[2] High Priority
    Events: stop, subagent
    Status: Enabled
    Priority: 100
    Exclusive: Yes
    [Edit] [Disable] [Delete]

[3] All Events
    Events: stop, permission_prompt, idle_prompt, subagent
    Status: Enabled
    [Edit] [Disable] [Delete]

Summary:
  3 groups enabled
  4 events in groups
  0 events ungrouped

[Configure] [Create] [Status]
```

---

## Audio Player Compatibility

Grouping doesn't play sounds:
- Management feature
- No player changes required

---

## Implementation

### Group Management

```go
type GroupManager struct {
    config   *GroupConfig
}

func (m *GroupManager) GetEventConfig(eventType string) (*EffectiveConfig, error) {
    group := m.findGroupForEvent(eventType)
    if group == nil {
        return nil, nil // No group, use default
    }

    if !group.Enabled {
        return &EffectiveConfig{
            Enabled: ptrBool(false),
            Reason:  "group disabled",
        }, nil
    }

    config := &EffectiveConfig{
        Enabled: ptrBool(true),
    }

    if group.Volume != nil {
        config.Volume = group.Volume
    }
    if group.Cooldown != nil {
        config.Cooldown = group.Cooldown
    }

    return config, nil
}

func (m *GroupManager) findGroupForEvent(eventType string) *EventGroup {
    for _, group := range m.config.Groups {
        for _, e := range group.Events {
            if e == eventType {
                return group
            }
        }
    }
    return nil
}

func (m *GroupManager) CheckExclusive(group *EventGroup, activeEvent string) (bool, string) {
    if !group.Exclusive {
        return true, ""
    }

    // Check if another event from this group is active
    for _, e := range group.Events {
        if e != activeEvent && m.state.IsEventActive(e) {
            return false, fmt.Sprintf("exclusive group: %s is playing", e)
        }
    }

    return true, ""
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

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event config
- [Profiles](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Similar grouping concept
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
