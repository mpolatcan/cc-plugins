# Feature: Sound Auditing

Audit trail for sound-related changes.

## Summary

Track all changes made to sound configurations for accountability.

## Motivation

- Track configuration changes
- Compliance requirements
- Debug configuration issues

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Audit Record

```go
type AuditRecord struct {
    ID          string    `json:"id"`
    Timestamp   time.Time `json:"timestamp"`
    Action      string    `json:"action"`      // create, update, delete
    EntityType  string    `json:"entity_type"` // sound, config, profile
    EntityID    string    `json:"entity_id"`
    OldValue    string    `json:"old_value,omitempty"`
    NewValue    string    `json:"new_value,omitempty"`
    User        string    `json:"user"`        // "system" or user
    Source      string    `json:"source"`      // CLI, API, etc.
}

type AuditConfig struct {
    Enabled       bool     `json:"enabled"`
    MaxRecords    int      `json:"max_records"`    // keep N records
    LogDir        string   `json:"log_dir"`
    IncludePlays  bool     `json:"include_plays"`  // log sound plays
    IncludeConfig bool     `json:"include_config"` // log config changes
}
```

### Audit Actions

| Action | Description | Example |
|--------|-------------|---------|
| config_update | Configuration changed | Volume modified |
| sound_add | New sound added | Custom sound imported |
| sound_delete | Sound removed | Custom sound deleted |
| profile_create | Profile created | New profile added |
| profile_delete | Profile deleted | Profile removed |
| sound_play | Sound played | Notification triggered |

### Commands

```bash
/ccbell:audit list                   # List audit records
/ccbell:audit show <id>              # Show record details
/ccbell:audit filter --action config_update
/ccbell:audit since "1 hour ago"     # Recent changes
/ccbell:audit user root              # Changes by user
/ccbell:audit export                 # Export audit log
/ccbell:audit cleanup --keep 1000    # Keep 1000 records
/ccbell:audit enable                 # Enable auditing
```

### Output

```
$ ccbell:audit list --since "1 hour ago"

=== Sound Audit Log ===

Records: 15 (last hour)

[1] 10:30:15 config_update
    User: system
    Event: stop
    Change: volume 0.5 -> 0.7
    [Show] [Revert] [Export]

[2] 10:28:03 sound_add
    User: cli
    Path: custom:my-sound
    [Show] [Details]

[3] 10:15:22 profile_create
    User: cli
    Profile: work-mode
    [Show] [Details]

...

[Show All] [Filter] [Export] [Settings]
```

---

## Audio Player Compatibility

Auditing doesn't play sounds:
- Logging feature
- No player changes required

---

## Implementation

### Record Creation

```go
func (a *AuditManager) Record(action, entityType, entityID string, oldVal, newVal interface{}) {
    if !a.config.Enabled {
        return
    }

    record := &AuditRecord{
        ID:         generateID(),
        Timestamp:  time.Now(),
        Action:     action,
        EntityType: entityType,
        EntityID:   entityID,
        User:       "cli", // TODO: get actual user
        Source:     "ccbell",
    }

    if oldVal != nil {
        record.OldValue = fmt.Sprintf("%v", oldVal)
    }
    if newVal != nil {
        record.NewValue = fmt.Sprintf("%v", newVal)
    }

    a.records = append([]*AuditRecord{record}, a.records...)

    // Trim to max records
    if len(a.records) > a.config.MaxRecords {
        a.records = a.records[:a.config.MaxRecords]
    }

    a.saveRecords()
}
```

### Query Filters

```go
func (a *AuditManager) Query(filter AuditFilter) []*AuditRecord {
    results := []*AuditRecord{}

    for _, record := range a.records {
        if filter.Action != "" && record.Action != filter.Action {
            continue
        }
        if filter.EntityType != "" && record.EntityType != filter.EntityType {
            continue
        }
        if filter.Since != nil && record.Timestamp.Before(*filter.Since) {
            continue
        }
        if filter.User != "" && record.User != filter.User {
            continue
        }
        results = append(results, record)
    }

    return results
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

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Config changes
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State changes

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
