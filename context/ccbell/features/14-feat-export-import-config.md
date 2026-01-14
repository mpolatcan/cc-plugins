# Feature: Export/Import Config

Share configurations via JSON files.

## Summary

Export current ccbell configuration to a portable JSON file. Import configurations from files or URLs.

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Nice to Have |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

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

## References

### ccbell Implementation Research

- [Current config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Base for export/import implementation
- [Config validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - `Validate()` method for imported configs
- [JSON marshaling](https://pkg.go.dev/encoding/json) - For config serialization
