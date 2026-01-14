# Feature: Sound Categories

Organize sounds into categories for easier browsing.

## Summary

Group sounds by category (alerts, bells, chimes, nature) for easier discovery.

## Motivation

- Browse sounds by type
- Find sounds faster
- Organize personal sound library

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Category Structure

```go
type SoundCategory struct {
    Name        string   `json:"name"`
    Description string   `json:"description"`
    Icon        string   `json:"icon"`        // emoji or icon name
    Sounds      []string `json:"sounds"`      // sound IDs
    Color       string   `json:"color"`       // display color
}

type CategoryStore struct {
    Categories map[string]*SoundCategory `json:"categories"`
    DefaultCategories map[string]*SoundCategory `json:"default_categories"`
}
```

### Default Categories

| Category | Icon | Description | Example Sounds |
|----------|------|-------------|----------------|
| Alerts | 🔔 | Attention-grabbing | stop, permission_prompt |
| Bells | 🔔 | Bell sounds | church, notification |
| Chimes | 🎐 | Soft chimes | wind, gentle |
| Nature | 🌿 | Nature sounds | birds, rain |
| Electronic | 🎵 | Synth sounds | digital, modern |
| Custom | 📁 | User sounds | personal library |

### Commands

```bash
/ccbell:category list             # List categories
/ccbell:category show alerts      # Show category sounds
/ccbell:category add mysounds     # Create category
/ccbell:category add alerts custom:*
/ccbell:category move bundled:stop alerts
/ccbell:category remove alerts    # Remove category (keep sounds)
/ccbell:category rename alerts notifications
```

### Output

```
$ ccbell:category list

=== Sound Categories ===

[🔔 Alerts] 5 sounds
    Attention-grabbing notification sounds
    bundled:stop, bundled:permission_prompt, custom:loud-bell

[🔔 Bells] 8 sounds
    Classic bell sounds
    bundled:bell, custom:church, custom:desk

[🎐 Chimes] 6 sounds
    Soft and gentle chimes
    bundled:gentle, custom:wind-chime

[🌿 Nature] 4 sounds
    Nature-inspired sounds
    custom:birds, custom:rain

[🎵 Electronic] 3 sounds
    Digital and synth sounds
    custom:beep, custom:digital

[📁 Custom] 12 sounds
    Personal sound library
    custom:*

Showing 6 categories (38 total sounds)
[Browse] [Edit] [Create] [Organize]
```

---

## Audio Player Compatibility

Sound categories don't play sounds:
- Organization feature
- No player changes required

---

## Implementation

### Category Browsing

```go
func (c *CategoryManager) GetCategorySounds(categoryName string) ([]*SoundInfo, error) {
    category, ok := c.categories[categoryName]
    if !ok {
        return nil, fmt.Errorf("category not found: %s", categoryName)
    }

    sounds := make([]*SoundInfo, 0, len(category.Sounds))
    for _, soundID := range category.Sounds {
        info, err := c.getSoundInfo(soundID)
        if err != nil {
            continue // Skip invalid sounds
        }
        sounds = append(sounds, info)
    }

    return sounds, nil
}
```

### Auto-Categorization

```go
func (c *CategoryManager) autoCategorize(sounds []string) {
    // Group by naming patterns
    patterns := map[string][]string{
        "alerts":      {"stop", "alert", "alarm", "warning"},
        "bells":       {"bell", "ding", "chime"},
        "chimes":      {"wind", "gentle", "soft"},
        "nature":      {"bird", "rain", "nature", "water"},
        "electronic":  {"digital", "beep", "synth", "modern"},
    }

    for _, sound := range sounds {
        categorized := false
        for category, keywords := range patterns {
            for _, keyword := range keywords {
                if strings.Contains(sound, keyword) {
                    c.categories[category].Sounds = append(c.categories[category].Sounds, sound)
                    categorized = true
                }
            }
        }
        if !categorized {
            c.categories["custom"].Sounds = append(c.categories["custom"].Sounds, sound)
        }
    }
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

- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound paths
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Sound references

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
