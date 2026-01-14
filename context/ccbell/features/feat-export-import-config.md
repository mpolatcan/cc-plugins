# Feature: Export/Import Config 📤

## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Benefit](#benefit)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Summary

Export current ccbell configuration to a portable JSON file. Import configurations from files or URLs.

## Motivation

- Share configurations with team members
- Backup and restore settings
- Quickly switch between different setups
- Support configuration templates

---

## Benefit

- **Team collaboration**: Standardize notification setups across development teams
- **Easy backup**: Protect configurations from accidental loss
- **Rapid onboarding**: New team members get productive instantly with shared configs
- **Experimentation safe**: Export before changes, import to restore if needed

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Nice to Have |
| **Complexity** | Low |
| **Category** | Config Management |

---

## Technical Feasibility

### Current Configuration Analysis

The current `internal/config/config.go` loads/saves from:
- `~/.claude/ccbell.config.json`

**Key Finding**: Export/import is straightforward JSON serialization.

### Export

```bash
/ccbell:config export
# Outputs to stdout

/ccbell:config export --file ~/ccbell-config.json
/ccbell:config export --redact   # Remove sensitive data
```

### Import

```bash
/ccbell:config import ~/ccbell-config.json
/ccbell:config import https://example.com/my-config.json
/ccbell:config import --dry-run   # Preview without applying
```

### Sanitization

```json
{
  "exported_at": "2026-01-14T10:30:00Z",
  "version": "0.2.30",
  "config": {
    // ... config without sensitive data
  }
}
```

---

## Feasibility Research

### Audio Player Compatibility

Export/import doesn't interact with audio playback. Pure config operation.

### External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

### Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Works with current architecture |
| Linux | ✅ Supported | Works with current architecture |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

## Implementation Notes

### Commands

```bash
/ccbell:config export [--file <path>] [--redact]
/ccbell:config import <path|url> [--dry-run] [--merge]
/ccbell:config share --url  # Upload to get shareable URL
```

### Validation

Validate imported config using existing `Config.Validate()` method.

---

## Claude Code Plugin Feasibility

| Aspect | Status | Notes |
|--------|--------|-------|
| **Hook Compatibility** | ✅ Compatible | Works with `Stop`, `Notification`, `SubagentStop` events |
| **Shell Execution** | ✅ Compatible | Uses standard shell commands |
| **Timeout Safe** | ✅ Safe | Fast execution, no timeout risk |
| **Dependencies** | ✅ Minimal | Uses built-in system commands |
| **Background Service** | ❌ Not Needed | Runs inline with notification |

### Implementation Notes

- Designed for Claude Code hook execution model
- Uses shell commands compatible with ccbell architecture
- No additional services or daemons required
- Works within 30-second hook timeout

---

## Repository Impact & Implementation

### ccbell Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | Add `Export(path string)` and `Import(path string)` methods |
| **Core Logic** | Modify | Add `SanitizeForExport()` to remove sensitive data |
| **Commands** | Add | New `config` command (export, import, share) |
| **New File** | Add | `internal/config/export.go` for export/import logic |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/config.md** | Add | New command documentation |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - internal/config/export.go:**
```go
func (c *Config) Export(path string, includeSecrets bool) error {
    exportCfg := c.DeepCopy()

    // Sanitize sensitive data for sharing
    if !includeSecrets {
        exportCfg.GlobalVolume = nil
        for _, event := range exportCfg.Events {
            event.Volume = nil
        }
    }

    // Remove internal fields
    exportCfg.Version = configVersion

    data, _ := json.MarshalIndent(exportCfg, "", "  ")
    return os.WriteFile(path, data, 0644)
}

func (c *Config) Import(path string, merge bool) error {
    data, err := os.ReadFile(path)
    if err != nil { return err }

    var imported Config
    if err := json.Unmarshal(data, &imported); err != nil {
        return fmt.Errorf("invalid config format: %w", err)
    }

    if err := imported.Validate(); err != nil {
        return fmt.Errorf("invalid config: %w", err)
    }

    if merge {
        return c.Merge(&imported)
    }
    *c = imported
    return nil
}

func (c *Config) Merge(other *Config) error {
    // Deep merge strategy
    if other.GlobalVolume != nil {
        c.GlobalVolume = other.GlobalVolume
    }
    for event, cfg := range other.Events {
        c.Events[event] = cfg
    }
    return nil
}
```

**ccbell - cmd/ccbell/main.go:**
```go
func main() {
    if len(os.Args) > 1 && os.Args[1] == "config" {
        handleConfigCommand(os.Args[2:])
        return
    }
}

func handleConfigCommand(args []string) {
    exportCmd := flag.NewFlagSet("export", flag.ExitOnError)
    importCmd := flag.NewFlagSet("import", flag.ExitOnError)
    outputFile := exportCmd.String("output", "-", "Output file (stdout if -)")

    switch args[0] {
    case "export":
        exportCmd.Parse(args[1:])
        cfg := config.Load(homeDir)
        cfg.Export(*outputFile, false)
    case "import":
        importCmd.Parse(args[1:])
        cfg := config.Load(homeDir)
        cfg.Import(args[1], true)
    }
}
```

---

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | New documentation | Create `commands/config.md` for export/import commands |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.3.0+
- **Config Schema Change**: No schema change, adds export/import commands
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/config.md` (new file with export, import, share commands)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag

### Implementation Checklist

- [ ] Create `commands/config.md` with export/import/share commands
- [ ] Document JSON export format and sanitization
- [ ] When ccbell v0.3.0+ releases, sync version to cc-plugins

---

## References

### ccbell Implementation Research

- [Current config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Base for export/import implementation
- [Config validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - `Validate()` method for imported configs
- [JSON marshaling](https://pkg.go.dev/encoding/json) - For config serialization

---

[Back to Feature Index](index.md)
