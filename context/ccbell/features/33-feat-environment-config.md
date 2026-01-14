# Feature: Environment-based Config

Load different configurations based on environment variables.

## Summary

Detect environment variables and automatically switch configuration profiles or settings based on detected context.

## Motivation

- Different configurations for different machines
- CI/CD vs development environments
- Support team-wide shared configurations

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Environment Detection

```go
// Check for known environment indicators
var environmentIndicators = map[string]string{
    "CI":              "ci",
    "GITPOD_WORKSPACE": "gitpod",
    "CODESPACES":      "codespaces",
    "TERM_PROGRAM":    "terminal",
}
```

### Config Structure

```json
{
  "environment_config": {
    "enabled": true,
    "variables": {
      "CCBELL_PROFILE": {
        "map": {
          "work": "work-profile",
          "home": "home-profile"
        }
      },
      "CI": {
        "value": "ci",
        "profile": "silent",
        "volume": 0.3
      }
    },
    "default_profile": "default"
  }
}
```

### Implementation

```go
func detectEnvironment() string {
    for env, indicator := range environmentIndicators {
        if os.Getenv(env) != "" {
            return indicator
        }
    }
    return "local"
}

func (c *CCBell) loadEnvironmentConfig() (*Config, error) {
    cfg, configPath, err := config.Load(c.homeDir)
    if err != nil {
        return nil, err
    }

    if c.envConfig == nil || !c.envConfig.Enabled {
        return cfg, nil
    }

    // Check CCBELL_PROFILE first
    if profile := os.Getenv("CCBELL_PROFILE"); profile != "" {
        if p, ok := c.envConfig.Variables["CCBELL_PROFILE"]; ok {
            if mapped, ok := p.Map[profile]; ok {
                cfg.ActiveProfile = mapped
            }
        }
    }

    // Check environment indicators
    env := detectEnvironment()
    if envConfig, ok := c.envConfig.Variables[env]; ok {
        if envConfig.Profile != "" {
            cfg.ActiveProfile = envConfig.Profile
        }
        if envConfig.Volume != 0 {
            for _, event := range config.ValidEvents {
                if cfg.Events[event] != nil {
                    v := envConfig.Volume
                    cfg.Events[event].Volume = &v
                }
            }
        }
    }

    return cfg, nil
}
```

### Commands

```bash
/ccbell:env detect        # Show detected environment
/ccbell:env status        # Show current config source
/ccbell:env list          # List environment variables
```

### Example Usage

```bash
# At work
export CCBELL_PROFILE=work
ccbell stop  # Uses work profile

# In CI
export CI=true
ccbell stop  # Uses silent profile, 30% volume

# At home
export CCBELL_PROFILE=home
ccbell stop  # Uses home profile
```

---

## Audio Player Compatibility

Environment-based config doesn't interact with audio playback:
- Purely config loading logic
- No player changes required
- Same audio player regardless of env

---

## Implementation

### Config Changes

```go
type EnvironmentConfig struct {
    Enabled        bool                   `json:"enabled"`
    Variables      map[string]*EnvVarConfig `json:"variables"`
    DefaultProfile string                 `json:"default_profile"`
}

type EnvVarConfig struct {
    Variable string             `json:"variable,omitempty"`
    Value    string             `json:"value,omitempty"`
    Map      map[string]string  `json:"map,omitempty"`
    Profile  string             `json:"profile,omitempty"`
    Volume   float64            `json:"volume,omitempty"`
}
```

### Integration

```go
func main() {
    // Load base config
    cfg, configPath, err := config.Load(homeDir)

    // Apply environment overrides
    cfg, err = applyEnvironmentConfig(cfg)

    // Continue with normal flow
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

- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L81-L102) - Base loading logic
- [Profile handling](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L40-L43) - Profile structure
- [Main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Environment detection |
| Linux | ✅ Supported | Environment detection |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
