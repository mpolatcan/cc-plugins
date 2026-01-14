# Feature: Sound Tag Management

Add and manage tags for custom sounds.

## Summary

Tag sounds for organization and easier searching.

## Motivation

- Organize custom sounds
- Quick filtering and search
- Personal sound library

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Tag Storage

```go
type SoundTags struct {
    SoundPath string   `json:"sound_path"`
    Tags      []string `json:"tags"`
    Created   time.Time `json:"created"`
    Updated   time.Time `json:"updated"`
}

type TagStore struct {
    Tags    map[string]*SoundTags
    TagIndex map[string][]string  // tag -> sound paths
}
```

### Configuration

```json
{
  "tags": {
    "enabled": true,
    "store_path": "~/.claude/ccbell/tags.json"
  }
}
```

### Commands

```bash
/ccbell:tags add sound.aiff alert notification   # Add tags
/ccbell:tags add sound.aiff +urgent              # Add to existing
/ccbell:tags remove sound.aiff alert             # Remove tag
/ccbell:tags list                                # List all tags
/ccbell:tags list sound.aiff                     # List sound's tags
/ccbell:tags search alert                        # Find sounds with tag
/ccbell:tags search "alert || notification"      # OR search
/ccbell:tags export                              # Export tags
/ccbell:tags import tags.json                    # Import tags
```

### Output

```
$ ccbell:tags list

=== Sound Tags ===

alert:              3 sounds
  - custom/alert.aiff
  - custom/warning.aiff
  - packs/zen-bells/attention.aiff

notification:       5 sounds
  - custom/ping.aiff
  - custom/ding.aiff
  - ...

calm:               2 sounds
  - packs/zen-bells/peaceful.aiff
  - packs/zen-bells/serene.aiff

urgent:             1 sound
  - custom/emergency.aiff

$ ccbell:tags search calm

Sounds tagged with 'calm':
  [1] packs/zen-bells/peaceful.aiff
  [2] packs/zen-bells/serene.aiff
```

### Tag Operations

```go
func (t *TagStore) AddTag(soundPath string, tag string) error {
    if _, ok := t.Tags[soundPath]; !ok {
        t.Tags[soundPath] = &SoundTags{
            SoundPath: soundPath,
            Tags:      []string{},
            Created:   time.Now(),
        }
    }

    if !contains(t.Tags[soundPath].Tags, tag) {
        t.Tags[soundPath].Tags = append(t.Tags[soundPath].Tags, tag)
        t.TagIndex[tag] = append(t.TagIndex[tag], soundPath)
        t.Tags[soundPath].Updated = time.Now()
    }

    return t.Save()
}

func (t *TagStore) Search(query string) []string {
    // Parse query (support AND/OR)
    return t.tagIndex[query]
}
```

---

## Audio Player Compatibility

Tag management doesn't interact with audio playback:
- Pure metadata management
- No player changes required
- Affects sound selection only

---

## Implementation

### Tag Validation

```go
func validateTag(tag string) error {
    // Tag length limits
    if len(tag) < 2 || len(tag) > 20 {
        return errors.New("tag must be 2-20 characters")
    }

    // Allowed characters
    if !tagRegex.MatchString(tag) {
        return errors.New("tag must be alphanumeric with hyphens")
    }

    return nil
}
```

### Sound Integration

```go
func (c *CCBell) getTaggedSounds(tag string) []string {
    if c.tagStore == nil {
        return nil
    }
    return c.tagStore.Search(tag)
}

func (c *CCBell) getSoundTags(soundPath string) []string {
    if c.tagStore == nil {
        return nil
    }
    if tags, ok := c.tagStore.Tags[soundPath]; ok {
        return tags.Tags
    }
    return nil
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

- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound path handling
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Tag config
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Storage pattern

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
