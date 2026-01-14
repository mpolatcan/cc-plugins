# Feature: Sound Dependencies

Manage sound file dependencies and relationships.

## Summary

Track relationships between sounds and manage dependencies.

## Motivation

- Track sound relationships
- Cascade changes
- Analyze impact

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Dependency Types

| Type | Description | Example |
|------|-------------|---------|
| Parent | Sound is base for | custom:sound -> bundled:base |
| Child | Derived from parent | bundled:base -> custom:variant |
| UsedBy | Referenced by events | stop -> bundled:stop |
| References | References other sounds | chain -> sound1, sound2 |

### Configuration

```go
type SoundDependency struct {
    SoundID     string   `json:"sound_id"`
    SoundPath   string   `json:"sound_path"`
    Parent      string   `json:"parent,omitempty"`      // parent sound ID
    Children    []string `json:"children,omitempty"`    // derived sounds
    UsedBy      []string `json:"used_by,omitempty"`     // events using this
    References  []string `json:"references,omitempty"`  // sounds this references
    Hash        string   `json:"hash"`                  // sound file hash
}

type DependencyGraph struct {
    Sounds  map[string]*SoundDependency `json:"sounds"`
}
```

### Commands

```bash
/ccbell:deps show bundled:stop         # Show dependencies
/ccbell:deps tree                      # Show full tree
/ccbell:deps used-by custom:sound      # What uses this sound
/ccbell:deps children bundled:stop     # Show child sounds
/ccbell:deps validate                  # Validate dependencies
/ccbell:deps orphaned                  # Show orphaned sounds
/ccbell:deps broken                    # Show broken links
```

### Output

```
$ ccbell:deps tree

=== Sound Dependency Tree ===

bundled:stop
├── used_by: stop (event)
├── hash: a1b2c3d4
└── children: custom:my-stop

custom:my-stop
├── parent: bundled:stop
├── used_by: (none)
├── hash: e5f6g7h8
└── references: (none)

custom:alert
├── parent: (none)
├── used_by: permission_prompt (event)
├── hash: i9j0k1l2
└── references: bundled:base

Showing 3 sounds
[Validate] [Orphaned] [Broken]
```

---

## Audio Player Compatibility

Dependencies don't play sounds:
- Analysis feature
- No player changes required

---

## Implementation

### Dependency Detection

```go
func (d *DependencyManager) buildGraph() error {
    d.graph.Sounds = make(map[string]*SoundDependency)

    // Scan all sounds
    sounds := d.listAllSounds()

    for _, sound := range sounds {
        dep := &SoundDependency{
            SoundID:   sound.ID,
            SoundPath: sound.Path,
            Hash:      d.hashFile(sound.Path),
        }

        // Check for parent (by hash comparison or naming)
        parent := d.findParent(sound)
        if parent != "" {
            dep.Parent = parent
            d.graph.Sounds[parent].Children = append(d.graph.Sounds[parent].Children, sound.ID)
        }

        // Check what events use this sound
        for event, cfg := range d.config.Events {
            if cfg.Sound == sound.ID {
                dep.UsedBy = append(dep.UsedBy, event)
            }
        }

        d.graph.Sounds[sound.ID] = dep
    }

    return nil
}
```

### Validation

```go
func (d *DependencyManager) validate() []DependencyIssue {
    issues := []DependencyIssue{}

    for id, sound := range d.graph.Sounds {
        // Check if parent exists
        if sound.Parent != "" {
            if _, exists := d.graph.Sounds[sound.Parent]; !exists {
                issues = append(issues, DependencyIssue{
                    Sound:   id,
                    Type:    "missing_parent",
                    Message: fmt.Sprintf("Parent %s not found", sound.Parent),
                })
            }
        }

        // Check if file exists
        if _, err := os.Stat(sound.SoundPath); os.IsNotExist(err) {
            issues = append(issues, DependencyIssue{
                Sound:   id,
                Type:    "missing_file",
                Message: fmt.Sprintf("Sound file not found: %s", sound.SoundPath),
            })
        }
    }

    return issues
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

- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-155) - Dependency tracking
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event references

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
