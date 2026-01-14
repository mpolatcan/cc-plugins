# Feature: Sound Plugins

Plugin system for extending sound functionality.

## Summary

Extend ccbell functionality through a plugin architecture.

## Motivation

- Custom functionality
- Third-party extensions
- Modularity

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Plugin Types

| Type | Description | Example |
|------|-------------|---------|
| Processor | Audio post-processing | Custom effects |
| Source | Sound sources | HTTP streams |
| Notifier | Notification delivery | Slack, email |
| Trigger | Custom triggers | Time-based, API |

### Plugin Interface

```go
type Plugin interface {
    Name() string
    Version() string
    Initialize(config map[string]interface{}) error
    Shutdown() error
    Capabilities() []string
}

type ProcessorPlugin interface {
    Plugin
    Process(soundPath string, volume float64) (string, error)
}

type NotifierPlugin interface {
    Plugin
    Notify(title, message string) error
}

type TriggerPlugin interface {
    Plugin
    OnTrigger(eventType string) (string, error)
}
```

### Configuration

```go
type PluginConfig struct {
    Enabled   bool              `json:"enabled"`
    Plugins   map[string]*PluginSettings `json:"plugins"`
    SearchPath []string         `json:"search_path"` // plugin directories
}

type PluginSettings struct {
    Enabled   bool                   `json:"enabled"`
    Config    map[string]interface{} `json:"config"`
}
```

### Commands

```bash
/ccbell:plugin list                  # List plugins
/ccbell:plugin install myplugin      # Install plugin
/ccbell:plugin remove myplugin       # Remove plugin
/ccbell:plugin enable myplugin       # Enable plugin
/ccbell:plugin disable myplugin      # Disable plugin
/ccbell:plugin configure myplugin    # Configure plugin
/ccbell:plugin create myplugin       # Create plugin template
/ccbell:plugin info myplugin         # Show plugin info
```

### Output

```
$ ccbell:plugin list

=== Sound Plugins ===

[1] echo-effect (v1.0.0)
    Type: processor
    Status: Enabled
    Capabilities: [process]
    [Configure] [Disable] [Remove]

[2] http-stream (v0.5.0)
    Type: source
    Status: Disabled
    Capabilities: [stream]
    [Enable] [Configure] [Remove]

[3] slack-notify (v1.2.0)
    Type: notifier
    Status: Enabled
    Capabilities: [notify]
    [Configure] [Disable] [Remove]

[Install] [Create] [Marketplace]
```

---

## Audio Player Compatibility

Plugins work with existing audio player:
- Process sound before playback
- Same format support
- No player changes required

---

## Implementation

### Plugin Loader

```go
type PluginManager struct {
    plugins map[string]Plugin
    config  *PluginConfig
}

func (m *PluginManager) Load(pluginPath string) error {
    // Go plugins (.so files)
    if strings.HasSuffix(pluginPath, ".so") {
        return m.loadGoPlugin(pluginPath)
    }
    // Script plugins
    return m.loadScriptPlugin(pluginPath)
}

func (m *PluginManager) ExecuteProcessor(pluginName, soundPath string, volume float64) (string, error) {
    plugin, ok := m.plugins[pluginName]
    if !ok {
        return "", fmt.Errorf("plugin not found: %s", pluginName)
    }

    processor, ok := plugin.(ProcessorPlugin)
    if !ok {
        return "", fmt.Errorf("plugin %s is not a processor", pluginName)
    }

    return processor.Process(soundPath, volume)
}
```

### Plugin Template

```go
// Create a new plugin template
func (m *PluginManager) CreateTemplate(name, pluginType string) error {
    template := fmt.Sprintf(`package main

import "github.com/mpolatcan/ccbell/plugins"

type %s struct{}

func (p *%s) Name() string { return "%s" }
func (p *%s) Version() string { return "0.1.0" }
func (p *%s) Initialize(config map[string]interface{}) error { return nil }
func (p *%s) Shutdown() error { return nil }
func (p *%s) Capabilities() []string { return nil }

// Implement additional interfaces based on type
    `, name, name, name, name, name, name, name)

    return os.WriteFile(name+".go", []byte(template), 0644)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Go plugin system (pure Go) |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Plugin integration point

### Research Sources

- [Go plugins](https://pkg.go.dev/plugin)
- [Plugin pattern](https://en.wikipedia.org/wiki/Plug-in_(computing))

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via Go plugin |
| Linux | ✅ Supported | Via Go plugin |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
