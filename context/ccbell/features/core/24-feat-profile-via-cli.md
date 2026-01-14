# Feature: Profile Activation via CLI

Switch profiles without editing configuration files.

## Summary

Allow users to activate a different profile directly via command-line flag, overriding the configured active profile.

## Motivation

- Quick profile switching without config editing
- Test different profiles temporarily
- Integrate with shell scripts for workflow changes

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Current Profile Handling

The current `internal/config/config.go` stores `ActiveProfile` in config:
```go
type Config struct {
    ActiveProfile string              `json:"activeProfile"`
    Profiles      map[string]*Profile `json:"profiles,omitempty"`
}
```

**Key Finding**: Adding CLI profile override is a simple flag.

### Flag Implementation

```bash
ccbell stop --profile work
ccbell permission_prompt -p focus
ccbell subagent --profile silent
```

### Usage Scenarios

```bash
# Temporary profile for a task
ccbell stop --profile meetings  # Louder notifications during meetings

# Test a profile before committing
ccbell test all --profile zen-bells-sounds

# Use in scripts
ccbell stop --profile $CURRENT_PROFILE
```

---

## Audio Player Compatibility

Profile activation doesn't interact with audio playback:
- Only affects which config is used
- Same audio player regardless of profile
- No player changes required

---

## Implementation

### Flag Parsing

```go
var profileFlag = flag.String("profile", "", "Use specified profile (overrides config)")
var profileShort = flag.String("p", "", "Short form for --profile")

// In main.go
if *profileFlag != "" {
    profileName = *profileFlag
} else if *profileShort != "" {
    profileName = *profileShort
}
```

### Profile Resolution

```go
func getEffectiveProfile(cfg *Config, cliProfile string) string {
    if cliProfile != "" {
        // Validate profile exists
        if _, ok := cfg.Profiles[cliProfile]; !ok {
            log.Warn("Profile %q not found, using active profile", cliProfile)
            return cfg.ActiveProfile
        }
        return cliProfile
    }
    return cfg.ActiveProfile
}
```

### Commands

```bash
/ccbell:profile activate work   # Still available
ccbell stop --profile work     # CLI override
/ccbell:test --profile zen      # Test with profile
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## References

### ccbell Implementation Research

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Profile handling
- [GetEventConfig](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L179-L203) - Profile application logic
- [Main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Flag parsing location

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | CLI convenience |
| Linux | ✅ Supported | CLI convenience |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
