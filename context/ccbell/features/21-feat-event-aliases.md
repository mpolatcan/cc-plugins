# Feature: Event Aliases

Create shortcuts for event type names.

## Summary

Allow users to define short aliases for event types (e.g., `p` for `permission_prompt`) for quicker command usage.

## Motivation

- Shorter commands for frequent actions
- Personalize event names to match workflow
- Reduce typing for commonly used events

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Current Valid Events

The current `internal/config/config.go` defines:
```go
var ValidEvents = map[string]bool{
    "stop":              true,
    "permission_prompt": true,
    "idle_prompt":       true,
    "subagent":          true,
}
```

**Key Finding**: Adding aliases is a simple lookup before validation.

### Configuration

```json
{
  "aliases": {
    "p": "permission_prompt",
    "i": "idle_prompt",
    "s": "stop",
    "sub": "subagent",
    "perm": "permission_prompt"
  }
}
```

### Implementation

```go
// Alias resolution
func resolveAlias(eventType string, aliases map[string]string) string {
    if alias, ok := aliases[eventType]; ok {
        return alias
    }
    return eventType
}

// In ValidateEventType
func ValidateEventType(eventType string) error {
    // First check if it's a valid event
    if ValidEvents[eventType] {
        return nil
    }

    // Then check if it's an alias
    // Would need access to config aliases

    return fmt.Errorf("unknown event type: %s", eventType)
}
```

### Commands

```bash
ccbell p --dry-run              # permission_prompt
ccbell i --dry-run              # idle_prompt
ccbell sub --dry-run            # subagent

/ccbell:alias list              # List current aliases
/ccbell:alias add p permission_prompt
/ccbell:alias remove p
```

---

## Audio Player Compatibility

Event aliases don't interact with audio playback:
- Purely a command-line convenience feature
- No changes to player code required

---

## Implementation

### Config Changes

```go
type Config struct {
    Enabled       bool                `json:"enabled"`
    Debug         bool                `json:"debug"`
    ActiveProfile string              `json:"activeProfile"`
    QuietHours    *QuietHours         `json:"quietHours,omitempty"`
    Aliases       map[string]string   `json:"aliases,omitempty"`
    Events        map[string]*Event   `json:"events,omitempty"`
    Profiles      map[string]*Profile `json:"profiles,omitempty"`
}
```

### Alias Resolution

```go
func resolveEvent(eventType string, cfg *Config) string {
    // Direct match
    if _, ok := ValidEvents[eventType]; ok {
        return eventType
    }

    // Alias match
    if alias, ok := cfg.Aliases[eventType]; ok {
        if _, ok := ValidEvents[alias]; ok {
            return alias
        }
    }

    return eventType // Returns original, will fail validation
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

- [ValidEvents map](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L45-L51) - Base event types
- [ValidateEventType](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L223-L239) - Validation logic to extend
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - For adding aliases

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | CLI convenience |
| Linux | ✅ Supported | CLI convenience |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
