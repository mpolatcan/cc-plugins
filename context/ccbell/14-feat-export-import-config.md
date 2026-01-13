# Feature: Export/Import Config

Share configurations via JSON files.

## Summary

Export current ccbell configuration to a portable JSON file. Import configurations from files or URLs.

## Technical Feasibility

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

## Commands

```bash
/ccbell:config export [--file <path>] [--redact]
/ccbell:config import <path|url> [--dry-run] [--merge]
/ccbell:config share --url  # Upload to get shareable URL
```
