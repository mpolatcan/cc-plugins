# Feature: Multi-Instance Support

Run multiple ccbell instances with different configurations.

## Summary

Allow running multiple ccbell processes with isolated configurations for different use cases.

## Motivation

- Different configurations for different projects
- Testing configurations without affecting main
- Separate notification channels

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Instance Isolation

| Component | Isolation Method |
|-----------|------------------|
| Config | `--config` flag |
| State | Instance-specific state file |
| Cache | Instance-specific cache |
| PID | Instance-specific PID file |

### Configuration

```json
{
  "instance": {
    "name": "work",
    "config_path": "~/.claude/ccbell-work.config.json",
    "state_path": "~/.claude/ccbell-work.state",
    "cache_dir": "~/.claude/ccbell-work-cache",
    "log_path": "~/.claude/ccbell-work.log"
  }
}
```

### Implementation

```go
type InstanceConfig struct {
    Name        string `json:"name"`
    ConfigPath  string `json:"config_path"`
    StatePath   string `json:"state_path"`
    CacheDir    string `json:"cache_dir"`
    LogPath     string `json:"log_path"`
}

func (c *CCBell) loadInstanceConfig(name string) (*InstanceConfig, error) {
    homeDir, _ := os.UserHomeDir()
    configPath := filepath.Join(homeDir, ".claude", "ccbell-instances.json")

    data, err := os.ReadFile(configPath)
    if err != nil {
        return nil, err
    }

    var instances map[string]*InstanceConfig
    json.Unmarshal(data, &instances)

    return instances[name], nil
}
```

### Commands

```bash
# Run specific instance
ccbell --instance work stop

# List instances
ccbell --instance list

# Create new instance
ccbell --instance create test --config test.json

# Copy configuration
ccbell --instance copy default test
```

### State Isolation

```go
func (c *CCBell) loadState() (*state.State, error) {
    statePath := c.instanceConfig.StatePath
    if statePath == "" {
        statePath = filepath.Join(c.homeDir, ".claude", "ccbell.state")
    }

    data, err := os.ReadFile(statePath)
    if err != nil {
        return &state.State{}, nil
    }

    var st state.State
    json.Unmarshal(data, &st)
    return &st, nil
}
```

### Hook Configuration

```json
{
  "hooks": [
    {
      "events": ["stop"],
      "matcher": "*",
      "type": "command",
      "command": "ccbell --instance work stop"
    }
  ]
}
```

---

## Audio Player Compatibility

Multi-instance uses same audio players:
- Each instance uses configured player
- No player changes required
- Players can be shared

---

## Implementation

### Instance Manager

```go
type InstanceManager struct {
    instancesDir string
}

func (m *InstanceManager) Create(name, configPath string) error {
    instDir := filepath.Join(m.instancesDir, name)
    os.MkdirAll(instDir, 0755)

    // Copy default config
    defaultConfig := filepath.Join(m.instancesDir, "..", "ccbell.config.json")
    os.Copy(defaultConfig, filepath.Join(instDir, "config.json"))

    return nil
}

func (m *InstanceManager) List() ([]string, error) {
    entries, err := os.ReadDir(m.instancesDir)
    // Filter and return instance names
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

- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L81-L102) - Config loading
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State persistence
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Main entry point

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | File-based isolation |
| Linux | ✅ Supported | File-based isolation |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
